-- 独立确定性验收入口，不作为发布主界面入口。
local App = require("gameplay.TestGroundApp")
---@type table?
local app = {}
local frame = 0
local checks = {} ---@type table[]
local maxRadiusError = 0.0
local maxSpeed = 0.0
local driveStart = Vector3.ZERO
local driveEnd = Vector3.ZERO
local yawLeft = 0.0
local rampContact = false
local wallContact = false
local menuDistance = 0.0
local previewMode = ""
for _,argument in ipairs(GetArguments()) do
    local mode=argument:match("^%-ground%-view=(%a+)$")
    if mode=="menu" or mode=="overview" or mode=="drive" or mode=="cleanup" then previewMode=mode end
end
local UI = require("urhox-libs/UI")

local function Check(name,passed,detail)
    checks[#checks+1]={name=name,passed=passed,detail=detail}
    print(string.format("[场地验收] %s %s %s",passed and "PASS" or "FAIL",name,detail or ""))
    if not passed then log:Write(LOG_ERROR,"[场地验收失败] "..name) end
end

local function CheckLayout()
    app.ui:Layout()
    UI.Layout()
    local w,h=UI.GetViewportSize()
    local widgets=app.mode=="drive" and
        {app.ui.returnButton,app.ui.resetButton,app.ui.cameraButton,app.ui.left,app.ui.right,
         app.ui.reverse,app.ui.brake,app.ui.throttle} or {app.ui.menu,app.ui.startButton,app.ui.overviewButton}
    local inside=true
    for _,widget in ipairs(widgets) do
        local rect=widget:GetAbsoluteLayout()
        if rect.x<0 or rect.y<0 or rect.x+rect.w>w+1 or rect.y+rect.h>h+1 or rect.w<1 or rect.h<1 then
            inside=false
            print("[场地布局] 越界 "..cjson.encode(rect))
        end
    end
    local menu=app.ui.menu:GetAbsoluteLayout()
    local footer=app.ui.footer:GetAbsoluteLayout()
    if app.mode~="drive" and app.ui.footer:IsVisible() and menu.y+menu.h>footer.y then inside=false end
    Check("UI可交互区域在屏幕内",inside,string.format("%s %.0fx%.0f基准像素",app.mode,w,h))
end

function Start()
    app=App.Create()
    -- 禁用外部输入，仅通过同一公开动作回调与屏幕按钮状态测试。
    app.ReadInput=function(self) self.controls=self.ui:ReadControls() end
    SubscribeToEvent(app.car.root,"NodeCollisionStart","HandleGroundTestCollision")
    SubscribeToEvent("Update","HandleGroundAcceptance")
    SubscribeToEvent("PostUpdate","HandleGroundAcceptanceCamera")
end

---@param eventType string
---@param eventData NodeCollisionStartEventData
function HandleGroundTestCollision(eventType,eventData)
    if not app then return end
    if not eventData:GetBool("Trigger") then
        local node=eventData:GetPtr("OtherNode")
        if node and node.name=="ImpactWall" then wallContact=true end
    end
end

local function MoveTo(position)
    app.car:Reset(position)
    app.settleTime=0
    app.accumulator=0
    app.samples={}
    app.lastPosition=position
    app.ui:ClearControls()
end

---@param eventType string
---@param eventData UpdateEventData
function HandleGroundAcceptance(eventType,eventData)
    if not app then return end
    frame=frame+1
    if previewMode~="" then
        if frame==1 and previewMode~="menu" and previewMode~="cleanup" then app:Action(previewMode) end
        app:Update(1/60)
        if frame==25 then
            CheckLayout()
            if previewMode=="cleanup" then
                local oldApp=app
                Stop()
                HandleGroundAcceptance(eventType,eventData)
                HandleGroundAcceptanceCamera(eventType,eventData)
                oldApp:Shutdown()
                oldApp:Update(1/60)
                oldApp:PostUpdate(1/60)
                Check("退出后回调与重复释放安全",app==nil and oldApp.closed,"")
                engine:Exit()
            end
        end
        return
    end
    if frame<=2400 then
        app:Update(1/60)
        local p=app.car:GetModelOrigin()
        local r=math.sqrt(p.x*p.x+p.z*p.z)
        maxRadiusError=math.max(maxRadiusError,math.abs(r-24))
        maxSpeed=math.max(maxSpeed,app.car.body.linearVelocity:Length())
    elseif frame==2401 then
        menuDistance=app.distance
        CheckLayout()
        Check("主界面真实运动",app.distance>125 and app.maxMenuDisplacement>45,string.format("里程%.1fm 位移%.1fm",app.distance,app.maxMenuDisplacement))
        Check("自动巡航保持环道",maxRadiusError<1.0,string.format("半径最大误差%.3fm",maxRadiusError))
        app.ui.startButton.props.onClick()
        app:Update(1/60)
        Check("开始试驾切换",app.mode=="drive" and not app.ui.menu:IsVisible() and app.ui.controls:IsVisible(),"按钮回调进入同一车辆")
        CheckLayout()
        MoveTo(Vector3(24,0.08,0))
        driveStart=app.car:GetModelOrigin()
    elseif frame<2581 then
        app.ui.throttle:SetState({pressed=true})
        app:Update(1/60)
    elseif frame==2581 then
        driveEnd=app.car:GetModelOrigin()
        Check("试驾油门有效",driveEnd.z-driveStart.z>3 and app.car.body.linearVelocity:Length()>2,tostring(driveEnd))
        app.ui:ClearControls()
        app.ui.brake:SetState({pressed=true})
        app:Update(1/60)
    elseif frame<2641 then
        app:Update(1/60)
    elseif frame==2641 then
        Check("屏幕刹车有效",app.car.body.linearVelocity:Length()<0.5,tostring(app.car.body.linearVelocity))
        MoveTo(Vector3(24,0.08,-5))
        app.ui.throttle:SetState({pressed=true})
        app.ui.left:SetState({pressed=true})
        app:Update(1/60)
    elseif frame<2821 then
        app:Update(1/60)
    elseif frame==2821 then
        yawLeft=app.car.root.worldRotation:YawAngle()
        Check("左转方向有效",yawLeft < -4 and yawLeft > -100,string.format("yaw=%.2f",yawLeft))
        MoveTo(Vector3(24,0.08,-5))
        app.ui.throttle:SetState({pressed=true})
        app.ui.right:SetState({pressed=true})
        app:Update(1/60)
    elseif frame<3001 then
        app:Update(1/60)
    elseif frame==3001 then
        local yaw=app.car.root.worldRotation:YawAngle()
        Check("右转方向有效",yaw>4 and yaw<100,string.format("yaw=%.2f",yaw))
        MoveTo(Vector3(24,0.08,0))
        app.ui.reverse:SetState({pressed=true})
        app:Update(1/60)
    elseif frame<3181 then app:Update(1/60)
    elseif frame==3181 then
        Check("倒车有效",app.car:GetModelOrigin().z < -2,tostring(app.car:GetModelOrigin()))
        MoveTo(Vector3(8,0.08,-11))
        app.ui.throttle:SetState({pressed=true})
        app:Update(1/60)
    elseif frame<3571 then
        app:Update(1/60)
        for _,sample in ipairs(app.samples) do
            if sample.grounded and sample.contact.y>0.18 and sample.contact.x>5 and sample.contact.x<11 then rampContact=true end
        end
    elseif frame==3571 then
        Check("悬挂坡实体接触",rampContact,"轮射线命中高于平地的斜坡")
        MoveTo(Vector3(0,0.08,7))
        app:Update(1/60)
    elseif frame==3631 then
        app.car.body.linearVelocity=Vector3(0,0,5)
        app:Update(1/60)
    elseif frame<3811 then app:Update(1/60)
    elseif frame==3811 then
        Check("场地防撞墙实体阻挡",wallContact and app.car:GetModelOrigin().z<11.3,tostring(app.car:GetModelOrigin()))
        app.ui.returnButton.props.onClick()
        app:Update(1/60)
        Check("返回实时主界面",app.mode=="menu" and app.ui.menu:IsVisible(),"")
        app.ui.overviewButton.props.onClick()
        app:Update(1/60)
        Check("全景模式仍运行",app.mode=="overview","")
        driveStart=app.car:GetModelOrigin()
    elseif frame<3991 then app:Update(1/60)
    elseif frame==3991 then
        Check("全景车辆继续运动",(app.car:GetModelOrigin()-driveStart):Length()>3,"")
        app.focused=false
        driveStart=app.car:GetModelOrigin()
        app:Update(1)
        Check("失焦暂停物理",(app.car:GetModelOrigin()-driveStart):Length()<0.001,"")
        app.focused=true
        app:Action("menu")
        local failures=0
        for _,check in ipairs(checks) do if not check.passed then failures=failures+1 end end
        print("[GROUND_REPORT] "..cjson.encode({result=failures==0 and "PASS" or "FAIL",checks=checks,
            radius_error_m=maxRadiusError,menu_max_speed_ms=maxSpeed,menu_distance_m=menuDistance}))
    end
end

---@param eventType string
---@param eventData PostUpdateEventData
function HandleGroundAcceptanceCamera(eventType,eventData)
    if app then app:PostUpdate(1/60) end
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    if app then
        UnsubscribeFromEvent(app.car.root,"NodeCollisionStart")
        app:Shutdown()
        app=nil
    end
end
