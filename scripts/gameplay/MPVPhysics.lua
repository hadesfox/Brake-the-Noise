-- 七座MPV独立物理适配；模型资源保持只读，车身与四轮物理不写回资产。
local MPVPhysics = {}
MPVPhysics.__index = MPVPhysics

local PREFAB = "model/mpv_seven_seat/Prefabs/OriginalMPV.prefab"
local COM_HEIGHT = 0.80
local REST_LENGTH = 0.45
local RADIUS = 0.429 -- 包含胎纹的实际网格半径。
local WHEEL_SPEC = {
    { name = "WheelFrontLeft", x = -1.04, z = 1.64, front = true },
    { name = "WheelFrontRight", x = 1.04, z = 1.64, front = true },
    { name = "WheelRearLeft", x = -1.04, z = -1.76, front = false },
    { name = "WheelRearRight", x = 1.04, z = -1.76, front = false },
}

---@class MPVWheelSample
---@field id integer
---@field name string
---@field grounded boolean
---@field length number
---@field position Vector3
---@field contact Vector3
---@field normal Vector3

-- 碰撞设计（单位米，+Z车头）：
-- 侧视：             ┌────车厢凸盒────┐
--                    │                │
--       ┌─车头凸盒────┤                │
--       └────────────底盘凸盒──────────┘
--            O                         O  四轮向-Y射线，不重复创建轮胎刚体。
-- 底盘：1.92×0.48×5.28，model-Y中心0.54；车厢：1.90×1.35×3.80。
-- 车身接触墙/地面产生刚体响应；悬挂只由RaycastVehicle求解。
-- 边界：射线不得命中自身；离地不能继续托举；单轮台阶不能变成四轮同动。
-- 这是外部阻挡碰撞，车厢凸盒不用于人员在车内行走，也非实体轮胎侧碰撞。

---@param scene Scene
---@return table
function MPVPhysics.Create(scene)
    local self = setmetatable({}, MPVPhysics)
    self:Init(scene)
    return self
end

---@param scene Scene
function MPVPhysics:Init(scene)
    self.root = scene:CreateChild("MPVPhysics", LOCAL)
    self.visual = scene:InstantiateXML(PREFAB, Vector3.ZERO, Quaternion.IDENTITY, LOCAL)
    assert(self.visual, "整车预制体实例化失败：" .. PREFAB)
    self.visual:SetParent(self.root)
    self.visual.position = Vector3(0, -COM_HEIGHT, 0)
    self.wheelNodes = {} ---@type Node[]
    self.wheelNames = {} ---@type string[]

    local models = self.visual:GetComponents("StaticModel", true)
    assert(#models == 16, "整车应有16个模型，实际 " .. #models)
    local materialCount = 0
    for _, model in ipairs(models) do
        assert(model.model, "缺少模型：" .. model.node.name)
        for slot = 0, model.numGeometries - 1 do
            local material = model:GetMaterial(slot)
            assert(material, "缺少材质：" .. model.node.name .. "/" .. slot)
            assert(material:GetTechnique(0), "材质Technique未加载：" .. material.name)
            materialCount = materialCount + 1
        end
    end
    assert(materialCount == 61, "应加载61个材质槽，实际 " .. materialCount)
    local steering = self.visual:GetChild("SteeringWheel", true)
    assert(steering and steering.position.x < 0, "左舵方向盘位置不正确")
    self.loadedModelCount = #models
    self.loadedMaterialCount = materialCount

    self.body = self.root:CreateComponent("RigidBody", LOCAL)
    self.body.mass = 1800 -- 验证用质量，不代表该车型实车整备质量。
    self.body.linearDamping = 0.08
    self.body.angularDamping = 0.30
    self.body.friction = 0.6
    self.body.restitution = 0.05
    self.body.collisionLayer = 2
    self.body.collisionMask = 1
    self.body.collisionEventMode = COLLISION_ALWAYS
    self.body.ccdRadius = 0.35
    self.body.ccdMotionThreshold = 0.20
    self.shapes = {} ---@type CollisionShape[]
    local boxes = {
        { size = Vector3(1.92, 0.48, 5.28), center = Vector3(0, 0.54, 0) },
        { size = Vector3(1.90, 1.35, 3.80), center = Vector3(0, 1.35, -0.62) },
        { size = Vector3(1.90, 0.45, 1.38), center = Vector3(0, 0.94, 1.94) },
    }
    for _, spec in ipairs(boxes) do
        local shape = self.root:CreateComponent("CollisionShape", LOCAL)
        shape:SetBox(spec.size, spec.center - Vector3(0, COM_HEIGHT, 0))
        shape.margin = 0.02
        table.insert(self.shapes, shape)
    end

    self.vehicle = self.root:CreateComponent("RaycastVehicle", LOCAL)
    self.vehicle:Init()
    self.vehicle:SetCoordinateSystem(IntVector3(0, 1, 2))
    for index, spec in ipairs(WHEEL_SPEC) do
        local node = self.visual:GetChild(spec.name, true)
        assert(node, "轮组缺失：" .. spec.name)
        node:SetParent(self.root)
        -- AddWheel节点位置是悬挂连接点；静态网格轮心不能直接当连接点。
        -- 原生AddWheel把node局部位置保存为连接点，但求解时连接点相对刚体重心。
        -- 因此初始化需扣除复合形状自动计算的centerOfMass，而非直接使用模型坐标。
        node.position = Vector3(spec.x, 0.44 + REST_LENGTH - COM_HEIGHT, spec.z) - self.body.centerOfMass
        self.vehicle:AddWheel(node, Vector3(0, -1, 0), Vector3(-1, 0, 0), REST_LENGTH, RADIUS, spec.front)
        -- Lua数组从1起；引擎wheel ID为0起，运行时连接点断言验证此转换。
        local wheelId = index - 1
        self.vehicle:SetWheelSuspensionStiffness(wheelId, 35.0)
        self.vehicle:SetWheelDampingRelaxation(wheelId, 4.4)
        self.vehicle:SetWheelDampingCompression(wheelId, 2.8)
        self.vehicle:SetWheelFrictionSlip(wheelId, 2.2)
        self.vehicle:SetWheelRollInfluence(wheelId, 0.15)
        self.vehicle:SetMaxSuspensionTravel(wheelId, 25.0) -- 原生接口沿用厘米；采样检查米制行程。
        self.wheelNodes[index] = node
        self.wheelNames[index] = spec.name
    end
    assert(self.vehicle:GetNumWheels() == 4, "四轮悬挂初始化失败")
    for index, spec in ipairs(WHEEL_SPEC) do
        local id = index - 1
        local connection = self.vehicle:GetWheelConnectionPoint(id) + self.body.centerOfMass
        assert(math.abs(connection.x - spec.x) < 0.001 and math.abs(connection.z - spec.z) < 0.001,
            "轮连接点/索引异常：" .. spec.name .. " " .. tostring(connection))
    end
    print(string.format("[MPV] 真实加载：%d模型/%d材质槽；质量=%.0fkg，重心=%s",
        #models, materialCount, self.body.mass, tostring(self.body.centerOfMass)))
    self:Reset(Vector3(0, 0.08, 0))
end

---@param modelOrigin Vector3
function MPVPhysics:Reset(modelOrigin)
    self.body:SetTransform(modelOrigin + Vector3(0, COM_HEIGHT, 0), Quaternion.IDENTITY)
    self.body.linearVelocity = Vector3.ZERO
    self.body.angularVelocity = Vector3.ZERO
    self.body:ResetForces()
    self.body:Activate()
    self.vehicle:ResetSuspension()
    self:SetControls(0, 0, 120)
end

---@param engineForce number
---@param steeringDegrees number
---@param brake number
function MPVPhysics:SetControls(engineForce, steeringDegrees, brake)
    for index = 1, 4 do
        local id = index - 1
        self.vehicle:SetEngineForce(id, engineForce)
        self.vehicle:SetBrake(id, brake)
        self.vehicle:SetSteeringValue(id, index <= 2 and steeringDegrees or 0)
    end
end

---@return MPVWheelSample[]
function MPVPhysics:Sample()
    local result = {} ---@type MPVWheelSample[]
    local down = self.root.worldRotation * Vector3(0, -1, 0)
    for index = 1, 4 do
        local id = index - 1
        local grounded = self.vehicle:WheelIsGrounded(id)
        -- 先保存接地结果再刷新轮变换：刷新会清除此标记。
        -- 手工物理步进时显式写回节点，避免重置后等待自动PostUpdate造成一帧滞后。
        self.vehicle:UpdateWheelTransform(id, false)
        local position = self.vehicle:GetWheelPosition(id)
        self.wheelNodes[index].worldPosition = position
        self.wheelNodes[index].worldRotation = self.vehicle:GetWheelRotation(id)
        local anchor = self.root:LocalToWorld(self.vehicle:GetWheelConnectionPoint(id) + self.body.centerOfMass)
        local length = (position - anchor):DotProduct(down)
        result[index] = {
            id = id, name = self.wheelNames[index], grounded = grounded,
            length = length, position = position, contact = self.vehicle:GetContactPosition(id),
            normal = self.vehicle:GetContactNormal(id),
        }
    end
    return result
end

---@return Vector3
function MPVPhysics:GetModelOrigin()
    return self.root:LocalToWorld(Vector3(0, -COM_HEIGHT, 0))
end

return MPVPhysics
