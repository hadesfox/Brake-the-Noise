-- 基于scaffold-3d-scene的场景构建：低模山谷试车场，所有长度单位为米。
local Ground = {}
Ground.__index = Ground

-- 碰撞规划（俯视，+Z向上）：
--             环形道路：半径24，宽8，连续平地射线支撑
--       ┌──────────────────────────────────┐
--       │       减速带      缓坡平台         │
--       │       x=-8        x=8            │
--       │               中央维修坪         │
--       │     停车棚         防撞墙         │
--       └──────────────────────────────────┘
-- 地面厚1m；环道标线仅渲染不碰撞；测试坡采用闭合凸包与同一网格碰撞。
-- 周边围挡与防撞墙实体阻挡；锥桶为标记，不做可飞散刚体。
-- 缓坡最大高0.8m，坡长8m，避免短陡坡让长轴距车身直接托底。

function Ground.Create(scene)
    local self = setmetatable({}, Ground)
    self:Init(scene)
    return self
end

function Ground:Material(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.9))
    mat.cullMode = CULL_NONE
    self.materials[#self.materials + 1] = mat
    return mat
end

function Ground:Mesh(name, model, position, size, mat, rotation)
    local node = self.scene:CreateChild(name, LOCAL)
    node.position = position
    node.rotation = rotation or Quaternion.IDENTITY
    local visual = node:CreateChild("Visual", LOCAL)
    local dimensions = model.boundingBox.size
    visual.scale = Vector3(size.x / dimensions.x, size.y / dimensions.y, size.z / dimensions.z)
    local rendererModel = visual:CreateComponent("StaticModel", LOCAL)
    rendererModel.model = model
    rendererModel.material = mat
    rendererModel.castShadows = true
    return node
end

function Ground:Box(name, position, size, mat, solid, rotation)
    local node = self:Mesh(name, self.box, position, size, mat, rotation)
    if solid then
        local body = node:CreateComponent("RigidBody", LOCAL)
        body.collisionLayer = 1
        body.collisionMask = 3 -- 同时接受车身组2与车轮射线组1。
        body.friction = 0.9
        node:CreateComponent("CollisionShape", LOCAL):SetBox(size)
    end
    return node
end

function Ground:Ring(name, inner, outer, y, mat)
    local node = self.scene:CreateChild(name, LOCAL)
    local geom = node:CreateComponent("CustomGeometry", LOCAL)
    geom:BeginGeometry(0, TRIANGLE_LIST)
    for index = 1, 96 do
        local a, b = (index - 1) * math.pi / 48, index * math.pi / 48
        local p1 = Vector3(inner * math.cos(a), y, inner * math.sin(a))
        local p2 = Vector3(outer * math.cos(a), y, outer * math.sin(a))
        local p3 = Vector3(outer * math.cos(b), y, outer * math.sin(b))
        local p4 = Vector3(inner * math.cos(b), y, inner * math.sin(b))
        for _, point in ipairs({p1, p3, p2, p1, p4, p3}) do
            geom:DefineVertex(point)
            geom:DefineNormal(Vector3.UP)
            geom:DefineTexCoord(Vector2(point.x, point.z))
        end
    end
    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function Ground:Cone(x, z)
    self:Box("ConeBase", Vector3(x, 0.025, z), Vector3(0.55, 0.05, 0.55), self.ink, false)
    self:Mesh("TrafficCone", self.cone, Vector3(x, 0.30, z), Vector3(0.42, 0.55, 0.42), self.orange)
    self:Mesh("ConeStripe", self.cylinder, Vector3(x, 0.28, z), Vector3(0.26, 0.09, 0.26), self.cream)
end

function Ground:Ramp(x, z)
    local points = {
        Vector3(-2.8, 0, -4), Vector3(2.8, 0, -4),
        Vector3(-2.8, 0, 4), Vector3(2.8, 0, 4),
        Vector3(-2.8, 0.8, 4), Vector3(2.8, 0.8, 4),
    }
    local model = ConvexGeometry(points):ToModel()
    local node = self.scene:CreateChild("SuspensionRamp", LOCAL)
    node.position = Vector3(x, 0.015, z)
    local sm = node:CreateComponent("StaticModel", LOCAL)
    sm.model, sm.material = model, self.concrete
    sm.castShadows = true
    local body = node:CreateComponent("RigidBody", LOCAL)
    body.collisionLayer, body.collisionMask = 1, 3
    node:CreateComponent("CollisionShape", LOCAL):SetConvexHull(model)
    self:Box("RampPlateau", Vector3(x, 0.415, z + 7), Vector3(5.6, 0.8, 6), self.concrete, true)
    for side = -1, 1, 2 do
        self:Box("RampSide", Vector3(x + side * 2.95, 0.45, z + 4), Vector3(0.12, 0.9, 11), self.orange, false)
    end
end

function Ground:Init(scene)
    self.scene = scene
    self.materials = {} ---@type Material[]
    self.box = cache:GetResource("Model", "Models/Box.mdl")
    self.cone = cache:GetResource("Model", "Models/Cone.mdl")
    self.cylinder = cache:GetResource("Model", "Models/Cylinder.mdl")
    assert(self.box and self.cone and self.cylinder, "场地基础模型未加载")
    self.ink = self:Material(Color(0.08, 0.13, 0.14))
    self.asphalt = self:Material(Color(0.20, 0.25, 0.25))
    self.cream = self:Material(Color(0.88, 0.87, 0.72))
    self.orange = self:Material(Color(0.92, 0.40, 0.13))
    self.grass = self:Material(Color(0.37, 0.47, 0.31))
    self.concrete = self:Material(Color(0.60, 0.61, 0.53))
    self.teal = self:Material(Color(0.20, 0.46, 0.43))
    self.pine = self:Material(Color(0.18, 0.33, 0.26))
    self.trunk = self:Material(Color(0.29, 0.25, 0.18))
    self.mountain = self:Material(Color(0.34, 0.43, 0.36))
    self:Lighting()
    self:Box("Ground", Vector3(0, -0.5, 0), Vector3(150, 1, 150), self.grass, true)
    self:Ring("LoopRoad", 20, 28, 0.012, self.asphalt)
    self:Ring("InnerLine", 20.3, 20.42, 0.02, self.cream)
    self:Ring("OuterLine", 27.58, 27.7, 0.02, self.cream)
    for index = 1, 48 do
        local theta = (index - 1) * math.pi / 24
        local rotation = Quaternion(-theta * 180 / math.pi, Vector3.UP)
        self:Box("LaneDash", Vector3(24 * math.cos(theta), 0.023, 24 * math.sin(theta)),
            Vector3(0.12, 0.012, 1.3), self.cream, false, rotation)
        local curb = index % 2 == 0 and self.cream or self.orange
        self:Box("RoadCurb", Vector3(28.2 * math.cos(theta), 0.08, 28.2 * math.sin(theta)),
            Vector3(0.45, 0.16, 3.3), curb, true, rotation)
    end
    self:Box("Paddock", Vector3(0, -0.015, 0), Vector3(32, 0.05, 32), self.asphalt, false)
    self:Box("AccessLane", Vector3(18, -0.015, 0), Vector3(12, 0.05, 9), self.asphalt, false)
    for index = 1, 4 do
        self:Box("SpeedBump", Vector3(-8, 0.045, -3 + index * 2.5), Vector3(5.5, 0.09, 0.45), self.orange, true)
    end
    self:Ramp(8, -3)
    self:Box("ImpactWall", Vector3(0, 0.75, 14), Vector3(6, 1.5, 0.55), self.concrete, true)
    for index = 1, 6 do
        self:Box("ImpactStripe", Vector3(-3.1 + index * 0.9, 0.78, 13.71), Vector3(0.32, 1.4, 0.035), self.orange, false)
    end
    for _, p in ipairs({{-12,-9},{-4,-9},{4,-9},{12,-9},{-12,11},{-4,11},{4,11},{12,11}}) do self:Cone(p[1],p[2]) end
    self:Box("Workshop", Vector3(-7, 1.8, -14), Vector3(13, 3.6, 4), self.cream, true)
    self:Box("WorkshopRoof", Vector3(-7, 3.75, -13), Vector3(15, 0.3, 7), self.teal, false)
    for index = 1, 3 do
        self:Box("GarageDoor", Vector3(-14 + index * 3.5, 1.4, -11.98), Vector3(2.9, 2.8, 0.06), self.ink, false)
        self:Box("GarageHeader", Vector3(-14 + index * 3.5, 3.1, -11.94), Vector3(2.9, 0.22, 0.06), self.orange, false)
    end
    -- 起点计时门在环道东侧，横跨车道但净高4.8m。
    for _, x in ipairs({19.4,28.6}) do
        self:Box("TimingGatePost", Vector3(x, 2.4, 2), Vector3(0.25, 4.8, 0.25), self.ink, true)
    end
    self:Box("TimingGateBeam", Vector3(24, 4.8, 2), Vector3(9.5, 0.32, 0.32), self.teal, true)
    for index = 1, 9 do
        self:Box("StartMark", Vector3(19.5 + index, 0.028, 1.8), Vector3(0.52, 0.015, 1.2),
            index % 2 == 0 and self.ink or self.cream, false)
    end
    for index = 1, 28 do
        local a = index * 2.39996
        local r = 43 + index % 5 * 4
        local x,z = r * math.cos(a),r * math.sin(a)
        local h = 4 + index % 4
        self:Mesh("PineTrunk", self.cylinder, Vector3(x,h*0.3,z), Vector3(0.35,h*0.6,0.35), self.trunk)
        self:Mesh("PineCrown", self.cone, Vector3(x,h*0.65,z), Vector3(h*0.7,h*0.8,h*0.7), self.pine)
    end
    for index = 1, 12 do
        local a = index * math.pi / 6
        local h = 12 + index % 4 * 6
        self:Mesh("Mountain", self.cone, Vector3(100*math.cos(a),h/2-1,100*math.sin(a)),
            Vector3(42,h,38), self.mountain)
    end
    self.windFlag = self:Box("WindFlag", Vector3(31,3.8,3), Vector3(1.7,0.7,0.06), self.orange, false)
    self:Box("FlagPole", Vector3(30.1,2,3),Vector3(0.07,4,0.07),self.ink,false)
    print("[试车场] 场地完成：环道半径24m、减速带、缓坡、维修区和碰撞区")
end

function Ground:Lighting()
    local lg = self.scene:CreateChild("LightGroup", LOCAL)
    local xml = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    assert(xml, "场景灯光预设缺失")
    local root = xml:GetRoot()
    local attr = root:GetChild("component"):GetChild("attribute")
    while attr:NotNull() do
        if attr:GetAttribute("name") == "Vignette Texture" then attr:SetAttribute("value", "Texture2D;") end
        attr = attr:GetNext("attribute")
    end
    assert(lg:LoadXML(root), "场景灯光加载失败")
    local zone = lg:GetComponent("Zone", true)
    zone.ambientSource = AMBIENT_COLOR
    zone.ambientColor = Color(0.27,0.29,0.25)
    zone.fogColor = Color(0.69,0.75,0.68)
    zone.fogStart, zone.fogEnd = 65, 160
    zone.tonemapMode = TONEMAP_MODE_ACES
    local sun = lg:GetComponent("Light", true)
    sun.color = Color(1,0.91,0.73)
    sun.brightness = 1.5
    -- 使用Zone的背景色，不创建会引用缺失默认天空贴图的Skybox组件。
end

function Ground:Update(time)
    self.windFlag.rotation = Quaternion(0, math.sin(time * 1.6) * 12, math.sin(time * 2) * 3)
end

return Ground
