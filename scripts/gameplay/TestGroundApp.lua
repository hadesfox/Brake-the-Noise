-- 基于scaffold-3d-scene：固定构图、静态车与人物，仅提供主菜单热点。
local GroundScene=require("gameplay.TestGroundScene")
local GroundUI=require("ui.TestGroundMenu")
local App={}
App.__index=App

function App.Create()
    local self=setmetatable({},App)
    self:Init()
    return self
end

function App:Init()
    self.scene=Scene()
    self.scene:CreateComponent("Octree")
    self.ground=GroundScene.Create(self.scene)
    local prefab=cache:GetResource("XMLFile","model/mpv_seven_seat/Prefabs/OriginalMPV.prefab")
    assert(prefab,"主界面车辆预制体缺失")
    -- 车头朝世界+X；固定相机看向车头与左侧车身，不改变车辆模型或材质。
    self.car=self.scene:InstantiateXML(prefab:GetRoot(),Vector3(0,0.015,0),Quaternion(0,90,0),LOCAL)
    assert(self.car,"主界面车辆加载失败")
    self.car.name="MenuParkedMPV"
    -- 直接从已交付模型的实际包围盒贴地，不启动载具物理或持续修正位置。
    local minimumY=math.huge
    local materialCount=0
    local drawables=self.car:GetComponents("StaticModel",true)
    for _,drawable in ipairs(drawables) do
        assert(drawable.model,"车辆部件模型缺失")
        minimumY=math.min(minimumY,drawable.worldBoundingBox.min.y)
        materialCount=materialCount+drawable.numGeometries
    end
    local carPosition=self.car.position
    self.car.position=Vector3(carPosition.x,carPosition.y+(0.015-minimumY),carPosition.z)
    self.person=self.ground.person
    self.cameraNode=self.scene:CreateChild("MenuCamera",LOCAL)
    self.camera=self.cameraNode:CreateComponent("Camera",LOCAL)
    self.camera.nearClip=0.1
    self.camera.farClip=1800
    self.camera.fov=35
    self.focused=true
    self.closed=false
    self.pendingAction=""
    self.selected=""
    self.pointerDown={} ---@type table<number,table>
    self.viewportWidth=0.0
    self.viewportHeight=0.0
    -- 热点规划（车辆局部坐标，+Z车头；整车已转向画面右侧）：
    -- 可见侧为车辆局部 +X；车门 z=+0.7、后侧车身 z=-1.7，拾取盒互不重叠。
    -- 射线先转到各对象局部，取最近命中；入口按钮在左侧留白区排列。
    -- 只做主界面拾取，不创建人物/车身碰撞或进入测试流程。
    self.hotspots={
        {id="person",title="人物 · 占位",node=self.person,anchor=Vector3(0,1.30,0),
            bounds=BoundingBox(Vector3(-0.53,0,-0.25),Vector3(0.61,2.06,0.28)),offset=Vector2(-150,30)},
        {id="start",title="开始测试",node=self.car,anchor=Vector3(1.02,1.08,0.7),
            bounds=BoundingBox(Vector3(0.78,0.52,0.08),Vector3(1.22,1.80,1.30)),offset=Vector2(-170,-40)},
        {id="archive",title="测试档案",node=self.car,anchor=Vector3(1.02,1.05,-1.7),
            bounds=BoundingBox(Vector3(0.75,0.45,-2.10),Vector3(1.25,1.80,-1.30)),offset=Vector2(-170,-40)},
    }
    self.ui=GroundUI.Create(self.hotspots,function(action)self.pendingAction=action end,
        function(event,kind)self:Pointer(event,kind)end)
    renderer.hdrRendering=true
    renderer:SetNumViewports(1)
    renderer:SetViewport(0,Viewport:new(self.scene,self.camera))
    input.mouseMode=MM_ABSOLUTE
    self:PostUpdate(0)
    print(string.format("[直道主界面] 静态车辆%d模型/%d材质槽；热点：人物、车门、后侧车身",#drawables,materialCount))
end

function App:Pick(x,y)
    local width,height=self.ui:GetViewportSize()
    if width<=0 or height<=0 then return "" end
    local ray=self.camera:GetScreenRay(x/width,y/height)
    local closest=math.huge
    local selected=""
    for _,hotspot in ipairs(self.hotspots) do
        local localRay=ray:Transformed(hotspot.node.worldTransform:Inverse())
        local distance=localRay:HitDistance(hotspot.bounds)
        if distance>=0 and distance<closest and distance<80 then
            closest=distance
            selected=hotspot.id
        end
    end
    return selected
end

function App:Pointer(event,kind)
    if self.closed or not self.focused then return end
    local id=event.pointerId
    if kind=="move" then
        self.ui:SetHover(self:Pick(event.x,event.y))
    elseif kind=="cancel" then
        self.pointerDown[id]=nil
        self.ui:SetHover("")
    elseif event:IsPrimaryAction() then
        if kind=="down" then
            self.pointerDown[id]={x=event.x,y=event.y,target=self:Pick(event.x,event.y)}
        elseif kind=="up" then
            local pressed=self.pointerDown[id]
            self.pointerDown[id]=nil
            if pressed and pressed.target~="" and
                (event.x-pressed.x)^2+(event.y-pressed.y)^2<=100 and
                self:Pick(event.x,event.y)==pressed.target then
                self.pendingAction=pressed.target
            end
        end
    end
end

function App:Action(id)
    if self.closed then return end
    if id=="close" then
        self.selected=""
        self.ui:CloseSelection()
        return
    end
    for _,hotspot in ipairs(self.hotspots) do
        if hotspot.id==id then
            self.selected=id
            self.ui:ShowSelection(id)
            print("[直道主界面] 点击入口："..id.."；仅界面占位反馈，不启动玩法")
            return
        end
    end
end

function App:SetFocused(focused)
    self.focused=focused
    self.pointerDown={}
    self.ui:SetHover("")
end

function App:Update(dt)
    if self.closed or not self.focused then return end
    if self.pendingAction~="" then
        local action=self.pendingAction
        self.pendingAction=""
        self:Action(action)
    end
    if input:GetKeyPress(KEY_ESCAPE) then self:Action("close") end
end

function App:PostUpdate(dt)
    if self.closed then return end
    local width,height=self.ui:GetViewportSize()
    if width~=self.viewportWidth or height~=self.viewportHeight then
        self.viewportWidth=width
        self.viewportHeight=height
        -- 参考构图：低机位前侧3/4视角，车辆居中偏下、人物在右侧，左侧保留入口空间。
        -- MPV比参考跑车更高，保留真实尺寸，不为模仿轮廓压扁模型。
        -- 窄屏保持同一水平视角后退；机位不随负Y偏移降到地面以下。
        local target=Vector3(0.10,1.48,0.06)
        local viewOffset=Vector3(7.66,-0.83,-4.99)
        local aspect=width/math.max(height,1)
        local framingScale=math.max(1,1.6/math.max(aspect,0.1))
        local cameraPosition=target+viewOffset*framingScale
        self.cameraNode.position=Vector3(cameraPosition.x,0.65,cameraPosition.z)
        self.cameraNode:LookAt(target)
        print(string.format("[直道主界面] 前侧3/4参考构图 %.2f:1，机位缩放%.2f，FOV %.0f",aspect,framingScale,self.camera.fov))
    end
    self.ui:UpdateAnchors(self.camera)
end

function App:Shutdown()
    if self.closed then return end
    self.closed=true
    self.pointerDown={}
    self.ui:Shutdown()
    renderer:SetNumViewports(0)
    self.scene:Dispose()
    print("[直道主界面] 已关闭")
end

return App
