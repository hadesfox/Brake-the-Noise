-- 基于templates/scaffold-3d-scene.lua：独立MPV加载、碰撞与悬挂测试入口。
local UI = require("urhox-libs/UI")
local MPVPhysics = require("gameplay.MPVPhysics")

---@type Scene
local scene
---@type PhysicsWorld
local physics
---@type Node
local cameraNode
---@type Node
local block
---@type Node
local wall
---@type table
local car = {}
---@type Label
local statusLabel
---@type Label
local wheelLabel
local debugDraw = true
local simulationStep = 0
local phase = 1
local phaseStep = 0
local checks = {} ---@type table[]
local snapshots = {} ---@type table[]
local latestSamples = {} ---@type MPVWheelSample[]
local finished = false
local wallContacts = 0
local floorContacts = 0
local restingFloorContacts = 0
local baseline = 0.0
local stableMin = math.huge
local stableMax = -math.huge
local maxTravelSpread = 0.0
local baselineLengths = {} ---@type number[]
local maxLeftCompression = 0.0
local maxFrontAsymmetry = 0.0
local visualFrames = 0
local maxVisualPositionError = 0.0
local minVisualAxleAlignment = 1.0
local maxWallZ = -math.huge
local airborneFrames = 0
local autoRun = true
local PHASES = { "落地稳定性", "单轮台阶受压", "离地与回弹", "车身撞墙阻挡", "完成" }

local function Check(name, passed, detail)
    checks[#checks + 1] = { name = name, passed = passed, detail = detail }
    print(string.format("[MPV测试] %s %s：%s", passed and "PASS" or "FAIL", name, detail))
    if not passed then log:Write(LOG_ERROR, "[MPV测试失败] " .. name .. ": " .. detail) end
end

local function MaterialFor(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.9))
    return mat
end

local function StaticBox(name, position, size, color)
    local node = scene:CreateChild(name, LOCAL)
    node.position = position
    local visual = node:CreateChild("Visual", LOCAL)
    visual.scale = size
    local model = visual:CreateComponent("StaticModel", LOCAL)
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    assert(model.model and math.abs(model.model.boundingBox.size.x - 1) < 0.001, "内置Box尺寸异常")
    model.material = MaterialFor(color)
    local body = node:CreateComponent("RigidBody", LOCAL)
    body.collisionLayer = 1
    -- 原生车轮射线使用默认查询组1；地面mask必须同时接受该查询组与车身组2。
    body.collisionMask = 3
    local shape = node:CreateComponent("CollisionShape", LOCAL)
    shape:SetBox(size)
    return node
end

local function SaveSnapshot(samples)
    local origin = car:GetModelOrigin()
    local data = { phase = PHASES[phase], step = simulationStep,
        origin = { origin.x, origin.y, origin.z }, velocity = car.body.linearVelocity:Length(), wheels = {} }
    for i, sample in ipairs(samples) do
        data.wheels[i] = { name = sample.name, grounded = sample.grounded, length = sample.length,
            position = { sample.position.x, sample.position.y, sample.position.z },
            contact = { sample.contact.x, sample.contact.y, sample.contact.z },
            y = sample.position.y, contactY = sample.contact.y }
    end
    snapshots[#snapshots + 1] = data
end

local function Finish()
    if finished then return end
    Check("四轮渲染节点同步", visualFrames >= 100 and maxVisualPositionError < 0.01 and minVisualAxleAlignment > 0.999,
        string.format("%d帧，轮心最大误差%.5fm，轮轴最小对齐度%.5f", visualFrames, maxVisualPositionError, minVisualAxleAlignment))
    finished = true
    local failed = 0
    for _, check in ipairs(checks) do if not check.passed then failed = failed + 1 end end
    local report = {
        result = failed == 0 and "PASS" or "FAIL", checks = checks, snapshots = snapshots,
        loaded_models = car.loadedModelCount, loaded_material_slots = car.loadedMaterialCount,
        wall_contacts = wallContacts, chassis_floor_contacts = floorContacts,
        resting_chassis_floor_contacts = restingFloorContacts, physics_steps = simulationStep,
        test_mass_kg = car.body.mass,
        heavy_load_limit = "2400kg实测前轴超出每轮6000N原生支撑上限，托底；1800kg通过不代表重载通过",
        suspension = { rest_length_m = 0.45, stiffness = 35, damping_compression = 2.8,
            damping_relaxation = 4.4, maximum_observed_spread_m = maxTravelSpread,
            left_front_compression_from_baseline_m = maxLeftCompression,
            maximum_front_axle_asymmetry_m = maxFrontAsymmetry },
        visual_sync = { frames = visualFrames, maximum_wheel_position_error_m = maxVisualPositionError,
            minimum_axle_alignment = minVisualAxleAlignment },
        limitations = { "射线轮胎没有独立轮胎侧壁碰撞", "简化外部车身凸盒不支持车内人员碰撞",
            "未验证多人同步、高速工况或移动端性能" },
    }
    local file = File(GetContext(), "mpv-physics-report.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(report))
        file:Close()
    end
    print("[MPV_REPORT] " .. cjson.encode(report))
    phase = 5
    print(string.format("[MPV测试] 完成 %d项，失败%d项；报告 mpv-physics-report.json", #checks, failed))
end

local function SetupScene()
    scene = Scene()
    scene:CreateComponent("Octree")
    scene:CreateComponent("DebugRenderer")
    physics = scene:CreateComponent("PhysicsWorld")
    physics.gravity = Vector3(0, -9.81, 0)
    physics.fps = 120
    physics.maxSubSteps = 1
    physics.numIterations = 20
    physics.interpolation = false
    -- 确定性测试：每个Update只执行两个1/120秒物理步，不受离屏帧速影响。
    physics.updateEnabled = false
    local lightGroup = scene:CreateChild("LightGroup", LOCAL)
    local lighting = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    assert(lighting, "光照资源加载失败")
    -- 测试运行时未附带预设中的编辑器暗角纹理；在加载前移除关闭状态的该引用。
    local lightingRoot = lighting:GetRoot()
    local zoneXML = lightingRoot:GetChild("component")
    local attribute = zoneXML:GetChild("attribute")
    while attribute:NotNull() do
        if attribute:GetAttribute("name") == "Vignette Texture" then
            attribute:SetAttribute("value", "Texture2D;")
        end
        attribute = attribute:GetNext("attribute")
    end
    assert(lightGroup:LoadXML(lightingRoot), "光照节点初始化失败")
    local zone = lightGroup:GetComponent("Zone", true)
    zone.fogStart = 60
    zone.fogEnd = 120
    zone.ambientSource = AMBIENT_COLOR
    zone.ambientColor = Color(0.35, 0.35, 0.38)
    renderer.hdrRendering = true
    StaticBox("Ground", Vector3(0, -0.5, 0), Vector3(35, 1, 40), Color(0.23, 0.28, 0.32))
    block = StaticBox("SingleWheelBlock", Vector3(-1.04, 0.09, 1.64), Vector3(0.65, 0.18, 0.75), Color(0.87, 0.59, 0.19))
    wall = StaticBox("Wall", Vector3(0, 1.5, 5.0), Vector3(7, 3, 0.5), Color(0.55, 0.25, 0.23))
    block:SetEnabledRecursive(false)
    wall:SetEnabledRecursive(false)
    car = MPVPhysics.Create(scene)
    cameraNode = scene:CreateChild("Camera", LOCAL)
    cameraNode.position = Vector3(-7.5, 4.2, 8.8)
    cameraNode:LookAt(Vector3(0, 1.0, 0))
    local camera = cameraNode:CreateComponent("Camera", LOCAL)
    camera.nearClip = 0.05
    camera.farClip = 120
    camera.fov = 48
    renderer:SetViewport(0, Viewport:new(scene, camera))
    Check("引擎加载模型及材质", car.loadedModelCount == 16 and car.loadedMaterialCount == 61, "16模型、61材质槽")
    Check("左舵及四轮连接点", car.vehicle:GetNumWheels() == 4, "左舵与连接点断言通过")
end

local function SetupUI()
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT,
        fonts = { { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf", bold = "Fonts/MiSans-Regular.ttf" } } },
    })
    statusLabel = UI.Label { text = "初始化", fontSize = 16 }
    wheelLabel = UI.Label { text = "轮组采样等待", fontSize = 13, whiteSpace = "normal" }
    UI.SetRoot(UI.Panel {
        width = "100%", height = "100%", pointerEvents = "box-none",
        children = { UI.SafeAreaView {
            width = "100%", height = "100%", pointerEvents = "box-none",
            children = { UI.Panel {
                position = "absolute", top = 16, left = 16, width = 340, maxWidth = "95%",
                padding = 14, gap = 8, backgroundColor = { 20, 25, 34, 220 }, borderRadius = 8,
                children = {
                    UI.Label { text = "七座MPV · 物理验证", fontSize = 18 }, statusLabel, wheelLabel,
                    UI.Label { text = "Tab：碰撞线框  R：重跑  空格：暂停", fontSize = 12 },
                    UI.Button { text = "重跑自动验证", onClick = function() ResetTests() end },
                },
            } },
        } },
    })
end

function ResetTests()
    simulationStep = 0
    phase = 1
    phaseStep = 0
    checks = {}
    snapshots = {}
    latestSamples = {}
    Check("引擎加载模型及材质", car.loadedModelCount == 16 and car.loadedMaterialCount == 61, "16模型、61材质槽")
    Check("左舵及四轮连接点", car.vehicle:GetNumWheels() == 4, "初始化时左舵与连接点断言已通过")
    finished = false
    wallContacts = 0
    floorContacts = 0
    restingFloorContacts = 0
    stableMin = math.huge
    stableMax = -math.huge
    maxTravelSpread = 0
    baselineLengths = {}
    maxLeftCompression = 0
    maxFrontAsymmetry = 0
    visualFrames = 0
    maxVisualPositionError = 0
    minVisualAxleAlignment = 1
    maxWallZ = -math.huge
    airborneFrames = 0
    block:SetEnabledRecursive(false)
    wall:SetEnabledRecursive(false)
    car:Reset(Vector3(0, 0.08, 0))
    autoRun = true
end

---@param eventType string
---@param eventData NodeCollisionEventData
function HandleMPVCollision(eventType, eventData)
    if eventData:GetBool("Trigger") then return end
    local other = eventData:GetPtr("OtherNode")
    if other.name == "Wall" then wallContacts = wallContacts + 1 end
    if other.name == "Ground" then
        floorContacts = floorContacts + 1
        if phase == 1 and phaseStep + 1 >= 480 then restingFloorContacts = restingFloorContacts + 1 end
    end
end

local function AdvanceTests(samples)
    if finished then return end
    phaseStep = phaseStep + 1
    local grounded = 0
    local shortest = math.huge
    local longest = -math.huge
    for _, sample in ipairs(samples) do
        if sample.grounded then grounded = grounded + 1 end
        shortest = math.min(shortest, sample.length)
        longest = math.max(longest, sample.length)
        assert(sample.length == sample.length and math.abs(sample.length) < 5, "悬挂长度非有限或异常")
    end
    local origin = car:GetModelOrigin()
    if phaseStep % 120 == 0 then
        SaveSnapshot(samples)
        print(string.format("[MPV测试] %s t=%.2f y=%.3f 接地=%d L=%.3f..%.3f v=%.3f",
            PHASES[phase], phaseStep / 120, origin.y, grounded, shortest, longest, car.body.linearVelocity:Length()))
    end
    if phase == 1 then
        if phaseStep >= 480 then
            stableMin = math.min(stableMin, origin.y)
            stableMax = math.max(stableMax, origin.y)
        end
        if phaseStep == 720 then
            baseline = origin.y
            for index, sample in ipairs(samples) do baselineLengths[index] = sample.length end
            Check("静置四轮接地", grounded == 4, string.format("接地%d/4", grounded))
            Check("静置车身离地且未托底", origin.y > -0.22 and restingFloorContacts == 0,
                string.format("modelY=%.3f 稳定阶段托底%d次；落地瞬态接触%d次", origin.y, restingFloorContacts, floorContacts))
            Check("悬挂有压缩且稳定", grounded == 4 and shortest > 0.20 and longest < 0.445 and stableMax - stableMin < 0.02,
                string.format("长度%.3f..%.3f 波动%.4f", shortest, longest, stableMax - stableMin))
            block:SetEnabledRecursive(true)
            car:Reset(Vector3(0, baseline + 0.15, 0))
            phase = 2
            phaseStep = 0
        end
    elseif phase == 2 then
        if phaseStep >= 240 then
            maxTravelSpread = math.max(maxTravelSpread, longest - shortest)
            maxLeftCompression = math.max(maxLeftCompression, baselineLengths[1] - samples[1].length)
            maxFrontAsymmetry = math.max(maxFrontAsymmetry, samples[2].length - samples[1].length)
        end
        if phaseStep == 600 then
            -- 前后轴平地静载本来就不同；不能只凭四轮最大差判定单轮响应。
            Check("单轮台阶独立响应", maxLeftCompression > 0.06 and maxFrontAsymmetry > 0.06,
                string.format("左前轮较平地压缩%.3fm，同轴左右差%.3fm", maxLeftCompression, maxFrontAsymmetry))
            local hit = samples[1]
            Check("左前轮命中台阶顶面", hit.grounded and math.abs(hit.contact.y - 0.18) < 0.02
                and math.abs(hit.contact.x + 1.04) < 0.335 and math.abs(hit.contact.z - 1.64) < 0.385
                and hit.normal.y > 0.95, "接触点 " .. tostring(hit.contact))
            Check("台阶后保持接地", grounded >= 3, string.format("接地%d/4", grounded))
            block:SetEnabledRecursive(false)
            car:Reset(Vector3(0, 1.35, 0))
            phase = 3
            phaseStep = 0
        end
    elseif phase == 3 then
        if phaseStep <= 12 and grounded == 0 and math.abs(shortest - 0.45) < 0.03
            and math.abs(longest - 0.45) < 0.03 then airborneFrames = airborneFrames + 1 end
        if phaseStep == 720 then
            Check("离地伸展且无假接地", airborneFrames >= 3, "离地有效步数 " .. airborneFrames)
            Check("落地阻尼恢复", grounded == 4 and car.body.linearVelocity:Length() < 0.12,
                string.format("接地%d/4 速度%.3f", grounded, car.body.linearVelocity:Length()))
            wall:SetEnabledRecursive(true)
            car:Reset(Vector3(0, baseline, 0))
            car:SetControls(0, 0, 0)
            car.body.linearVelocity = Vector3(0, 0, 5)
            phase = 4
            phaseStep = 0
        end
    elseif phase == 4 then
        maxWallZ = math.max(maxWallZ, origin.z)
        if phaseStep == 360 then
            Check("车身碰撞事件", wallContacts > 0, "撞墙事件 " .. wallContacts)
            Check("低速撞墙阻挡", maxWallZ < 2.15, string.format("modelZ最大%.3f；直立几何限值约2.11m，容差0.04m", maxWallZ))
            Finish()
        end
    end
end

function Start()
    local ok, err = pcall(function()
        SetupScene()
        SetupUI()
        SubscribeToEvent(car.root, "NodeCollision", "HandleMPVCollision")
        SubscribeToEvent("Update", "HandleVehicleUpdate")
        SubscribeToEvent("PostRenderUpdate", "HandleVehicleDebug")
    end)
    if not ok then log:Write(LOG_ERROR, "[MPV初始化失败] " .. tostring(err)); engine:Exit() end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleVehicleUpdate(eventType, eventData)
    if input:GetKeyPress(KEY_TAB) then debugDraw = not debugDraw end
    if input:GetKeyPress(KEY_SPACE) then autoRun = not autoRun end
    if input:GetKeyPress(KEY_R) then ResetTests() end
    if autoRun and not finished then
        local ok, err = pcall(function()
            for _ = 1, 2 do
                physics:Update(1 / 120)
                simulationStep = simulationStep + 1
                latestSamples = car:Sample()
                AdvanceTests(latestSamples)
                if phaseStep == 0 then latestSamples = {} end
            end
        end)
        if not ok then
            Check("运行时无错误", false, tostring(err))
            Finish()
        end
    end
    if simulationStep % 30 == 0 or finished then
        statusLabel:SetText(string.format("%s · 模拟 %.2f 秒", PHASES[phase], simulationStep / 120))
        local samples = latestSamples
        local lines = {}
        for _, sample in ipairs(samples) do
            lines[#lines + 1] = string.format("%s: %s / %.3fm", sample.name, sample.grounded and "接地" or "离地", sample.length)
        end
        wheelLabel:SetText(table.concat(lines, "\n"))
    end
end

---@param eventType string
---@param eventData PostRenderUpdateEventData
function HandleVehicleDebug(eventType, eventData)
    -- 原生PostUpdate写回车轮后，核对真实渲染节点而非只读物理内部轮心。
    -- 阶段切换会重置车身，跳过该帧的上一阶段快照。
    if not finished and phaseStep > 1 and #latestSamples == 4 then
        local bodyAxle = car.root.worldRotation * Vector3.RIGHT
        for index, sample in ipairs(latestSamples) do
            local wheelNode = car.wheelNodes[index]
            -- PostUpdate刷新轮心；按同一渲染相位比较，避免与物理阶段缓存跨相位比较。
            local renderedPhysicsPosition = car.vehicle:GetWheelPosition(index - 1)
            local visualError = (wheelNode.worldPosition - renderedPhysicsPosition):Length()
            if visualError > maxVisualPositionError + 0.02 then
                print(string.format("[MPV轮同步] %s 步%d %s 误差%.5f 节点%s 物理%s 速度%s",
                    PHASES[phase], simulationStep, sample.name, visualError, tostring(wheelNode.worldPosition),
                    tostring(renderedPhysicsPosition), tostring(car.body.linearVelocity)))
            end
            maxVisualPositionError = math.max(maxVisualPositionError, visualError)
            local wheelAxle = wheelNode.worldRotation * Vector3.RIGHT
            minVisualAxleAlignment = math.min(minVisualAxleAlignment, wheelAxle:DotProduct(bodyAxle))
        end
        visualFrames = visualFrames + 1
    end
    if not debugDraw then return end
    physics:DrawDebugGeometry(true)
    local rendererDebug = scene:GetComponent("DebugRenderer")
    -- 使用物理步末快照，避免渲染阶段的原生轮变换刷新清除接地标记。
    for index, sample in ipairs(latestSamples) do
        local anchor = car.root:LocalToWorld(car.vehicle:GetWheelConnectionPoint(index - 1) + car.body.centerOfMass)
        rendererDebug:AddLine(anchor, car.vehicle:GetWheelPosition(index - 1), sample.grounded and Color.GREEN or Color.RED, false)
    end
end

function Stop()
    UI.Shutdown()
    if scene then scene:Dispose() end
end
