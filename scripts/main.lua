-- 《舆论刹车》运行入口（骨架版）。
--
-- 流程：主界面 → 角色准备 → 驾驶舱 → 两轮判定 →（发帖/档案未实现）。
-- 规则内核（落点几何、力臂、接触映射、力度曲线）沿用已本地验证的模块，不在这里改动。
-- 本阶段目标是把"可见可操作的真实页面"串起来，美术用占位图形，正式素材按美术指南替换。
--
-- 明确未实现、且不在此处伪造的：损伤/断裂判定、温度与人体状态来源、刹车模拟、
-- 三次机会之外的完整结算、发帖与传播、结局、存档。踩空/踩油门后果按计划第 4.1 节留空。
local UI = require("urhox-libs/UI")
local DemoConfig = require("config.Demo")
local GameConfig = require("config.Game")
local FlowConfig = require("config.Flow")
local Parameters = require("core.Parameters")
local Contracts = require("core.Contracts")
local Session = require("core.Session")
local Landing = require("gameplay.Landing")
local ForceCurve = require("gameplay.ForceCurve")
local Lever = require("gameplay.Lever")
local ContactMapping = require("gameplay.ContactMapping")
local BrakingSimulation = require("gameplay.BrakingSimulation")
local StructureDamage = require("gameplay.StructureDamage")
local ActionGate = require("core.ActionGate")
local MainMenu = require("ui.MainMenu")
local CharacterPrep = require("ui.CharacterPrep")
local Boarding = require("ui.Boarding")
local PreDrive = require("ui.PreDrive")
local Cockpit = require("ui.Cockpit")
local Decision = require("ui.Decision")
local Archive = require("ui.Archive")
local BrakeTestDemo = require("ui.BrakeTestDemo")

-- 场景名。骨架阶段的真实页面顺序：
--   主界面 → 角色准备 → 上车过场 → 开车前准备 → 刹车时刻（判定）→ 发帖出口。
-- 清算、洪流、结局、档案仍为说明页或未实现。
local SCENE_MENU = "menu"
local SCENE_PREP = "prep"
local SCENE_BOARDING = "boarding"
local SCENE_PREDRIVE = "predrive"
local SCENE_COCKPIT = "cockpit"
local SCENE_DECISION = "decision"
local SCENE_ARCHIVE = "archive"
local SCENE_NOTICE = "notice"

---@type SessionModel?
local session = nil
---@type LandingModel?
local landing = nil
---@type ForceCurveModel?
local force = nil
local gate = ActionGate.Create()
local paused = false
local skipNextUpdate = false
-- 测试完成后等待手动确认进入下一轮
local waitingForResultConfirm = false
---@type string
local scene = SCENE_MENU
-- 驾驶舱内的两轮阶段，取值与 ui/BrakeTestDemo 的阶段常量一致。
---@type string
local phase = BrakeTestDemo.PHASE_LANDING
---@type CockpitView?
local cockpitView = nil
---@type BoardingView?
local boardingView = nil
---@type PreDriveView?
local preDriveView = nil
---@type LandingRecord?
local landingRecord = nil
-- 踩空/踩油门后停在的占位状态；非空时不再接受测试输入。
---@type string?
local pendingOutcome = nil
-- 角色准备的选择结果；上车过场与开车前准备都会用到。
---@type PrepSelection?
local prepSelection = nil
-- 最后一次测试的方案A结果（用于UI显示）
---@type table?
local lastTestResult = nil
-- 场景切换延迟到下一帧执行：避免在控件自己的事件回调里销毁控件树。
---@type fun()?
local deferredAction = nil

-- 前向声明：多个回调互相引用。定义处用赋值而非 `function` 语句，避免重定义告警。
---@type fun()
local GoToMenu

---@param action fun()
local function Defer(action)
    deferredAction = action
end

local function SetSceneRoot(root)
    UI.SetRoot(root, true)
    UI.Layout()
end

local function RefreshCockpit()
    if cockpitView and session and landing and force then
        local shoe = assert(DemoConfig.landing.shoes[landing.shoeIndex], "鞋型索引无效")
        cockpitView:RefreshHud(session, shoe.name)
        -- 传递是否等待确认的状态
        cockpitView.testView:Refresh(landing, force, phase, lastTestResult, waitingForResultConfirm)
    end
end

-- 骨架阶段的占位说明页：用于尚未实现的环节，明确标注未实现，不伪造内容。
---@param title string
---@param body string
local function BuildNotice(title, body)
    local card = UI.Card {
        width = "100%", maxWidth = 640, padding = 24, gap = 12,
        children = {
            UI.Label { text = title, fontSize = 22 },
            UI.Label { text = body, fontSize = 12, width = "100%", whiteSpace = "normal" },
            UI.Button {
                id = "noticeBack", text = "返回主界面", variant = "primary",
                height = 52, width = "100%",
                onClick = function() Defer(GoToMenu) end,
            },
        },
    }
    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = UI.Theme.Color("background"),
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%", nativeMenuInset = true, padding = 16,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexBasis = 0,
                        children = {
                            UI.Panel { width = "100%", alignItems = "center", paddingVertical = 8,
                                children = { card } },
                        },
                    },
                },
            },
        },
    }
end

function GoToMenu()
    scene = SCENE_MENU
    cockpitView = nil
    boardingView = nil
    preDriveView = nil
    prepSelection = nil
    pendingOutcome = nil
    landingRecord = nil
    waitingForResultConfirm = false  -- 重置状态
    gate:ClearHeld()
    SetSceneRoot(MainMenu.Create(function() Defer(StartTest) end,
        function() Defer(OpenArchive) end).root)
end

function OpenArchive()
    scene = SCENE_ARCHIVE
    SetSceneRoot(Archive.Create(function() Defer(GoToMenu) end).root)
end

function StartTest()
    session = Session.Create(FlowConfig, DemoConfig.landingSeed)
    landing = Landing.Create(DemoConfig.landing, DemoConfig.landingSeed)
    force = ForceCurve.Create(DemoConfig.force, DemoConfig.forceSeed)
    phase = BrakeTestDemo.PHASE_LANDING
    landingRecord = nil
    pendingOutcome = nil
    prepSelection = nil
    gate:ClearHeld()
    scene = SCENE_PREP
    local prep = CharacterPrep.Create(FlowConfig, DemoConfig.landing.shoes,
        function(selection) Defer(function() OnPrepConfirm(selection) end) end,
        function() Defer(GoToMenu) end)
    SetSceneRoot(prep.root)
    print(string.format("[会话] 开局 种子=%d 天气=%s 总机会=%d",
        session.seed, session.weatherId, session.flow.maxTests))
end

---@param selection PrepSelection
function OnPrepConfirm(selection)
    if not landing or not session then return end
    landing:SelectShoe(selection.shoeIndex)
    prepSelection = selection
    local shoe = assert(DemoConfig.landing.shoes[landing.shoeIndex], "鞋型索引无效")
    local clothing = assert(FlowConfig.character.clothing[selection.clothingIndex], "上衣索引无效")
    local trousers = assert(FlowConfig.character.trousers[selection.trousersIndex], "裤子索引无效")
    print(string.format("[会话] 角色确定 鞋=%s 上衣=%s 裤子=%s",
        shoe.id, clothing.id, trousers.id))
    -- 角色确定后先走过场，再进发车前准备。
    scene = SCENE_BOARDING
    boardingView = Boarding.Create(session:Weather(), shoe.name)
    SetSceneRoot(boardingView.root)
end

function GoToPreDrive()
    if not session or not landing then return end
    local shoe = assert(DemoConfig.landing.shoes[landing.shoeIndex], "鞋型索引无效")
    scene = SCENE_PREDRIVE
    boardingView = nil
    preDriveView = PreDrive.Create(FlowConfig, session:Weather(), shoe.name,
        function(selection) Defer(function() OnBrakeTime(selection) end) end)
    SetSceneRoot(preDriveView.root)
    print("[会话] 进入发车前准备；空调与座椅只做记录，不显示隐藏数值")
end

-- 加速到 100 km/h 后进入刹车时刻（判定轮）。
---@param selection PreDriveSelection
function OnBrakeTime(selection)
    if not session or not landing then return end
    print(string.format("[会话] 刹车时刻 空调=%s 座椅=%.2f（占位记录）",
        selection.acOn and "开" or "关", selection.seat))
    scene = SCENE_COCKPIT
    phase = BrakeTestDemo.PHASE_LANDING
    pendingOutcome = nil
    lastTestResult = nil  -- 清空上次结果
    waitingForResultConfirm = false  -- 重置状态
    preDriveView = nil
    -- 每次进入判定都从新的一次落点开始；换车沿用同一会话。
    if not landing.moving then landing:Start() end
    cockpitView = Cockpit.Create(DemoConfig.landing, {
        lever = DemoConfig.lever,
        contact = DemoConfig.contact,
        showDebugState = true, -- 骨架阶段打开开发读数；正式局必须关闭。
    }, FlowConfig, {
        onConfirm = Confirm,
        onSelect = SelectShoe,
        onPost = function() Defer(OnPost) end,
        onChangeVehicle = OnChangeVehicle,
        onBackToMenu = function() Defer(GoToMenu) end,
    })
    SetSceneRoot(cockpitView.root)
    RefreshCockpit()
end

function OnChangeVehicle()
    if not session then return end
    if scene ~= SCENE_COCKPIT and scene ~= SCENE_DECISION then return end
    if session:ChangeVehicle() then
        print(string.format("[会话] 换车 → 第 %d 台；总次数与历史不重置", session:VehicleIndex()))
        if scene == SCENE_COCKPIT then
            RefreshCockpit()
        else
            Defer(function() GoToDecision() end)
        end
    end
end

-- 测试后的独立选择界面：继续测试 / 发帖 / 换车。
function GoToDecision()
    if not session then return end
    scene = SCENE_DECISION
    cockpitView = nil
    local view = Decision.Create(session, {
        onContinue = function() Defer(OnContinueTest) end,
        onPost = function() Defer(OnPost) end,
        onChangeVehicle = OnChangeVehicle,
        onBackToMenu = function() Defer(GoToMenu) end,
    })
    SetSceneRoot(view.root)
end

-- 继续测试：回到发车前准备，重新走加速与刹车时刻；总次数与历史继续累计。
function OnContinueTest()
    if not session then return end
    GoToPreDrive()
end

function OnPost()
    if not session then return end
    if session:PostingState() == Session.POST_BLOCKED then return end
    -- 发帖属 D3，尚未实现；不伪造帖子内容与传播结果。
    scene = SCENE_NOTICE
    SetSceneRoot(BuildNotice("发帖（D3 未实现）",
        "已满足发帖时机（本次机会使用 " .. session:TestsUsed() .. "/" .. session.flow.maxTests
        .. "）。词条、标题/内容拼句、发送与传播规则尚未实现，因此这里只到流程出口，不生成任何帖子。"))
end

-- 两轮判定：落点一次确认、力度一次确认，各自按下即时锁定。
-- 落点结果为踩空/踩油门时，后果规则留空，会话停在占位页，不扣次也不免费重试。
---@param source string
function Confirm(source)
    if paused or scene ~= SCENE_COCKPIT or pendingOutcome then return end
    if not landing or not force or not session then return end
    if not gate:Accept(time:GetFrameNumber()) then return end
    -- 结果展示期间禁用确认操作
    if resultDisplayTimer > 0 then return end

    if phase == BrakeTestDemo.PHASE_LANDING then
        if not landing.moving then return end
        local record = landing:Lock(source)
        if not record then return end
        landingRecord = record
        if record.outcome == "brake" then
            phase = BrakeTestDemo.PHASE_FORCE
            force:Start()
            local armText = "无"
            if record.centroidX and record.centroidY then
                armText = string.format("%.4f",
                    Lever.Arm(DemoConfig.lever, record.centroidX, record.centroidY).l)
            end
            print(string.format(
                "[落点] 结果=brake 鞋=%s 鞋中心=(%.6f,%.6f) L=%s 面积=%.6f r踏板=%.4f r鞋底=%.4f",
                record.shoeId, record.x, record.y, armText,
                record.area, record.pedalCoverage, record.shoeCoverage))
        else
            pendingOutcome = record.outcome
            if cockpitView then cockpitView:ShowPending(record.outcome) end
            print(string.format("[落点] 结果=%s 鞋中心=(%.6f,%.6f) 后果规则留空，会话停在占位页",
                record.outcome, record.x, record.y))
        end
        RefreshCockpit()
        return
    end

    if phase == BrakeTestDemo.PHASE_FORCE then
        if not force.moving then return end
        local record = force:Lock(source)
        if not record then return end
        
        -- 方案A：计算接触、载荷、结构判定、制动模拟
        local leverResult = nil
        local contactResult = nil
        local torqueT = 0
        local hiddenDamageBefore = 0 -- TODO: 从车辆状态获取
        
        if landingRecord and landingRecord.centroidX and landingRecord.centroidY then
            -- 计算力臂
            leverResult = Lever.Arm(DemoConfig.lever, landingRecord.centroidX, landingRecord.centroidY)
            -- 计算接触映射
            contactResult = ContactMapping.Evaluate(DemoConfig.contact, 
                landingRecord.pedalCoverage, landingRecord.shoeCoverage)
            -- 计算载荷 T = F × L × A有效 × K姿势（K姿势暂用1.0占位）
            torqueT = record.force * leverResult.l * contactResult.effective * 1.0
        end
        
        -- 结构判定（二态：未断裂/断裂）
        local durabilityEffective = 1000 -- TODO: 从车辆配置获取 M有效
        local structureResult = StructureDamage.evaluate({
            torqueT = torqueT,
            durabilityEffective = durabilityEffective,
            hiddenDamageBefore = hiddenDamageBefore,
            pedalForce = record.force,
            conductionE = contactResult and contactResult.conduction or 0,
        })
        
        -- 制动模拟（纯逻辑，输出制动用时和距离）
        local brakingResult = BrakingSimulation.simulate({
            pedalForce = structureResult.actualPedalForce,
            brakeCurve = DemoConfig.braking.brakeCurve,
            resistance = DemoConfig.braking.resistance,
            initialSpeed = 100, -- km/h
            roadLength = DemoConfig.braking.roadLength,
            structureBroken = structureResult.broken,
        })
        
        -- 判定完成状态
        local completionStatus = "completed"
        local failureReason = nil
        if structureResult.broken then
            completionStatus = "failed_broken"
            failureReason = "刹车踏板断裂，制动力归零"
        elseif not brakingResult.stoppedInRoad then
            completionStatus = "failed_wall"
            failureReason = "未能在道路内停车"
        end
        
        -- 保存测试结果供UI显示
        lastTestResult = {
            leverArm = leverResult and leverResult.l or 0,
            concentrate = contactResult and contactResult.concentrate or 0,
            conduction = contactResult and contactResult.conduction or 0,
            effective = contactResult and contactResult.effective or 0,
            torqueT = torqueT,
            structureState = structureResult.structureState,
            brakingTime = brakingResult.brakingTime,
            brakingDistance = brakingResult.brakingDistance,
            actualPedalForce = structureResult.actualPedalForce,
            completionStatus = completionStatus,
            failureReason = failureReason,
        }
        
        -- 记录测试结果（方案A数据结构）
        local entry = {
            outcome = "brake",
            shoeId = landingRecord and landingRecord.shoeId or "unknown",
            landingX = landingRecord and landingRecord.x or nil,
            landingY = landingRecord and landingRecord.y or nil,
            pedalCoverage = landingRecord and landingRecord.pedalCoverage or nil,
            shoeCoverage = landingRecord and landingRecord.shoeCoverage or nil,
            intentForce = record.intentForce,
            force = record.force,
            breakState = structureResult.broken and Session.BREAK_ROOT or Session.BREAK_NONE, -- 保留兼容
            structureState = structureResult.structureState,
            source = source,
            reactionTime = 0, -- TODO: 从实际响应计时获取
            brakingTime = brakingResult.brakingTime,
            brakingDistance = brakingResult.brakingDistance,
            actualPedalForce = structureResult.actualPedalForce,
            completionStatus = completionStatus,
            failureReason = failureReason,
            hiddenDamageBefore = hiddenDamageBefore,
            hiddenDamageAfter = structureResult.hiddenDamageAfter,
        }
        local stored = session:RecordTest(entry)
        
        -- 输出日志（方案A成绩口径）
        print(string.format(
            "[测试] 第 %d 次（机会 %d/%d）F=%.1fN T=%.1f 结构=%s 制动用时=%.2fs 距离=%.1fm 状态=%s",
            stored.sequence, session:TestsUsed(), session.flow.maxTests,
            record.force, torqueT, structureResult.structureState,
            brakingResult.brakingTime, brakingResult.brakingDistance, completionStatus))
        
        phase = BrakeTestDemo.PHASE_LANDING
        landingRecord = nil
        -- 启动结果展示计时器，延迟跳转
        resultDisplayTimer = resultDisplayDuration
        -- 先刷新UI显示结果，不立即跳转
        RefreshCockpit()
        -- 跳转逻辑移到Update中的计时器处理
    end
end

---@param index integer
function SelectShoe(index)
    -- 正式流程在角色准备阶段定鞋，测试中不允许换鞋。
    -- 保留函数以匹配测试组件接口，但不执行换鞋；索引参数仅为接口一致而存在。
    local _ = index
end

function Start()
    graphics.windowTitle = DemoConfig.title
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true
    UI.Init({
        theme = "default-taptap",
        scale = UI.Scale.DEFAULT,
        fonts = { { family = "sans", weights = {
            normal = "Fonts/MiSans-Regular.ttf",
            bold = "Fonts/MiSans-Regular.ttf",
        } } },
    })
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("InputFocus", "HandleInputFocus")
    GoToMenu()
    print("[舆论刹车] 骨架版启动，数据契约版本=" .. Contracts.schemaVersion
        .. "，流程配置=" .. FlowConfig.version)
    for _, group in ipairs({ "testing", "human", "component" }) do
        local issues = Parameters.Check(GameConfig, group)
        print(string.format("[配置] 分组=%s 正式参数待补=%d 项；当前只运行开发几何与曲线",
            group, #issues))
    end
    print(string.format("[配置] 踩空策略=%s 踩油门策略=%s（留空时停在占位页，不代决定）",
        FlowConfig.outcomePolicy.missed, FlowConfig.outcomePolicy.throttle))
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("KeyUp")
    UnsubscribeFromEvent("InputFocus")
    UI.Shutdown()
    cockpitView = nil
    session = nil
    landing = nil
    force = nil
    gate:ClearHeld()
    print("[舆论刹车] 已清理")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if deferredAction then
        local action = deferredAction
        deferredAction = nil
        action()
        return
    end
    if paused then return end
    if skipNextUpdate then
        skipNextUpdate = false
        return
    end
    local dt = eventData:GetFloat("TimeStep")
    
    -- 结果展示延迟计时器
    if resultDisplayTimer > 0 then
        resultDisplayTimer = resultDisplayTimer - dt
        if resultDisplayTimer <= 0 then
            resultDisplayTimer = 0
            -- 延迟结束，跳转到决策界面
            Defer(function() GoToDecision() end)
        end
        return
    end
    
    -- 发车前准备：推进加速计时，到达 100 km/h 后自动进入刹车时刻。
    if scene == SCENE_PREDRIVE and preDriveView then
        preDriveView:Update(dt)
        return
    end
    if scene ~= SCENE_COCKPIT or pendingOutcome then return end
    -- 只推进当前阶段，另一轮保持锁定。
    if phase == BrakeTestDemo.PHASE_LANDING and landing then
        landing:Update(dt)
    elseif phase == BrakeTestDemo.PHASE_FORCE and force then
        force:Update(dt)
    end
    RefreshCockpit()
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")
    if key ~= KEY_SPACE and key ~= KEY_RETURN then return end
    if not gate:Press(key, eventData:GetBool("Repeat")) then return end
    -- 上车过场：空格推进一段，走完自动进入发车前准备。
    if scene == SCENE_BOARDING then
        if boardingView and not boardingView:Advance() then Defer(GoToPreDrive) end
        return
    end
    if scene ~= SCENE_COCKPIT or pendingOutcome then return end
    Confirm("keyboard")
end

---@param eventType string
---@param eventData KeyUpEventData
function HandleKeyUp(eventType, eventData)
    gate:Release(eventData:GetInt("Key"))
end

---@param eventType string
---@param eventData InputFocusEventData
function HandleInputFocus(eventType, eventData)
    paused = not eventData:GetBool("Focus") or eventData:GetBool("Minimized")
    gate:ClearHeld()
    skipNextUpdate = not paused
    -- 驾驶舱的测试区在暂停时给出提示；其他页面不需要。
    if cockpitView then cockpitView.testView:ShowPaused(paused) end
    print("[会话] 焦点状态=" .. (paused and "暂停" or "恢复"))
end
