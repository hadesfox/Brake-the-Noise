-- 基于scaffold-3d-scene：仅搭建主界面的长直道与无外形设计的人物占位。
local Ground = {}
Ground.__index = Ground

function Ground.Create(scene)
    local self=setmetatable({},Ground)
    self:Init(scene)
    return self
end

function Ground:Material(color)
    local material=Material:new()
    material:SetTechnique(0,cache:GetResource("Technique","Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor",Variant(color))
    material:SetShaderParameter("Metallic",Variant(0.0))
    material:SetShaderParameter("Roughness",Variant(0.9))
    self.materials[#self.materials+1]=material
    return material
end

function Ground:Mesh(name,model,position,size,material,parent)
    local node=(parent or self.scene):CreateChild(name,LOCAL)
    node.position=position
    local dimensions=model.boundingBox.size
    node.scale=Vector3(size.x/dimensions.x,size.y/dimensions.y,size.z/dimensions.z)
    local drawable=node:CreateComponent("StaticModel",LOCAL)
    drawable.model=model
    drawable.material=material
    drawable.castShadows=true
    return node
end

function Ground:Box(name,position,size,material)
    return self:Mesh(name,self.box,position,size,material)
end

function Ground:Init(scene)
    self.scene=scene
    self.materials={} ---@type Material[]
    self.box=cache:GetResource("Model","Models/Box.mdl")
    self.sphere=cache:GetResource("Model","Models/Sphere.mdl")
    assert(self.box and self.sphere,"主界面基础模型加载失败")
    self.asphalt=self:Material(Color(0.19,0.22,0.23))
    self.line=self:Material(Color(0.85,0.84,0.75))
    self.shoulder=self:Material(Color(0.49,0.50,0.44))
    self.groundColor=self:Material(Color(0.41,0.46,0.36))
    self.placeholderColor=self:Material(Color(0.57,0.60,0.61))
    -- 长度仅为场景占位参数，本轮不制作零百计时、加速控制或赛道玩法。
    self.roadLength=1600
    self.roadStart=-40
    local centerZ=self.roadStart+self.roadLength/2
    self:Box("Ground",Vector3(0,-0.51,centerZ),Vector3(160,1,self.roadLength+160),self.groundColor)
    self.road=self:Box("AccelerationStraight",Vector3(0,-0.035,centerZ),Vector3(12,0.1,self.roadLength),self.asphalt)
    for _,x in ipairs({-6.1,6.1}) do
        self:Box("RoadShoulder",Vector3(x,-0.02,centerZ),Vector3(0.8,0.07,self.roadLength),self.shoulder)
        self:Box("RoadEdgeLine",Vector3(x*0.93,0.023,centerZ),Vector3(0.12,0.012,self.roadLength),self.line)
    end
    -- 车停在中央车道；两侧虚线不穿过车辆，用于强调直道纵深。
    for index=1,math.floor(self.roadLength/16) do
        local z=self.roadStart+(index-1)*16+4
        for _,x in ipairs({-3.2,3.2}) do
            self:Box("LaneDash",Vector3(x,0.024,z),Vector3(0.10,0.012,6),self.line)
        end
    end
    self:Box("StartLine",Vector3(0,0.024,4.5),Vector3(11.2,0.012,0.20),self.line)
    self:Lighting()
    self.person=self.scene:CreateChild("PersonPlaceholder",LOCAL)
    self.person.position=Vector3(-1.65,0.015,-1.95)
    self.person.rotation=Quaternion(0,174,0)
    -- 仍用灰色几何占位，不确定角色外形；正面亮相、双脚分开、单臂举拳、另一手叉腰。
    self:Mesh("HeadPlaceholder",self.sphere,Vector3(0,1.56,0.015),Vector3(0.34,0.38,0.34),self.placeholderColor,self.person)
    local torso=self:Mesh("TorsoPlaceholder",self.box,Vector3(0,1.15,0),Vector3(0.46,0.58,0.28),self.placeholderColor,self.person)
    torso.rotation=Quaternion(0,0,-4)
    for _,side in ipairs({-1,1}) do
        self:PoseLimb("ThighPlaceholder",Vector3(side*0.13,0.87,0),Vector3(side*0.19,0.47,0),0.18,0.20)
        self:PoseLimb("ShinPlaceholder",Vector3(side*0.19,0.47,0),Vector3(side*0.24,0.10,0.03),0.17,0.19)
        self:Mesh("FootPlaceholder",self.box,Vector3(side*0.24,0.055,0.08),Vector3(0.21,0.08,0.32),self.placeholderColor,self.person)
    end
    self:PoseLimb("VictoryUpperArm",Vector3(0.25,1.38,0),Vector3(0.47,1.66,0.01),0.14,0.16)
    self:PoseLimb("VictoryForearm",Vector3(0.47,1.66,0.01),Vector3(0.51,1.93,0.045),0.13,0.15)
    self:Mesh("VictoryFist",self.box,Vector3(0.51,1.96,0.045),Vector3(0.17,0.18,0.18),self.placeholderColor,self.person)
    self:PoseLimb("HipUpperArm",Vector3(-0.25,1.38,0),Vector3(-0.44,1.12,-0.04),0.14,0.16)
    self:PoseLimb("HipForearm",Vector3(-0.44,1.12,-0.04),Vector3(-0.23,0.99,0.17),0.13,0.15)
    self:Mesh("HipHand",self.box,Vector3(-0.23,0.99,0.17),Vector3(0.14,0.16,0.15),self.placeholderColor,self.person)
    print("[直道主界面] 长直道占位1600m，灰色车手举拳亮相；不加载环道和驾驶玩法")
end

function Ground:PoseLimb(name,startPoint,endPoint,width,depth)
    local direction=endPoint-startPoint
    local node=self:Mesh(name,self.box,(startPoint+endPoint)*0.5,Vector3(width,direction:Length(),depth),
        self.placeholderColor,self.person)
    node.rotation=Quaternion(Vector3.UP,direction:Normalized())
    return node
end

function Ground:Lighting()
    local node=self.scene:CreateChild("LightGroup",LOCAL)
    local xml=cache:GetResource("XMLFile","LightGroup/Daytime.xml")
    assert(xml,"主界面灯光预设缺失")
    local root=xml:GetRoot()
    local attribute=root:GetChild("component"):GetChild("attribute")
    while attribute:NotNull() do
        if attribute:GetAttribute("name")=="Vignette Texture" then attribute:SetAttribute("value","Texture2D;") end
        attribute=attribute:GetNext("attribute")
    end
    assert(node:LoadXML(root),"主界面灯光加载失败")
    local zone=node:GetComponent("Zone",true)
    zone.boundingBox=BoundingBox(Vector3(-2000,-2000,-2000),Vector3(2000,2000,2000))
    zone.ambientSource=AMBIENT_COLOR
    zone.ambientColor=Color(0.28,0.29,0.27)
    zone.fogColor=Color(0.73,0.77,0.73)
    zone.fogStart,zone.fogEnd=250,1700
    zone.tonemapMode=TONEMAP_MODE_ACES
    local sun=node:GetComponent("Light",true)
    sun.color=Color(1,0.94,0.82)
    sun.brightness=1.4
end

return Ground
