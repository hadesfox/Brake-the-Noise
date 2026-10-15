-- 仅验收本轮主界面：长直道、停车、人物占位和场景热点，不运行驾驶测试。
local App=require("gameplay.TestGroundApp")
local UI=require("urhox-libs/UI")
local PointerEvent=require("urhox-libs/UI/Core/PointerEvent")
---@type table?
local app
local frame=0
local initialCar=Vector3.ZERO
local initialPerson=Vector3.ZERO
local checks={} ---@type table[]

local function Check(name,passed)
    checks[#checks+1]={name=name,passed=passed}
    print("[主界面验收] "..(passed and "PASS " or "FAIL ")..name)
    if not passed then log:Write(LOG_ERROR,"[主界面验收失败] "..name) end
end

function Start()
    app=App.Create()
    initialCar=app.car.worldPosition
    initialPerson=app.person.worldPosition
    SubscribeToEvent("Update","HandleMenuAcceptance")
    SubscribeToEvent("PostUpdate","HandleMenuAcceptanceCamera")
end

local function CheckHotspots()
    local w,h=UI.GetViewportSize()
    local visible=true
    for _,hotspot in ipairs(app.hotspots) do
        local screen=app.camera:WorldToScreenPoint(hotspot.node:LocalToWorld(hotspot.anchor))
        local x,y=screen.x*w,screen.y*h
        Check("场景射线拾取 "..hotspot.id,app:Pick(x,y)==hotspot.id)
        local pointer={x=x,y=y,button=MOUSEB_LEFT,pointerId=1,pointerType="touch"}
        app.ui.sceneInput.props.onPointerDown(PointerEvent.new("PointerDown",pointer))
        app.ui.sceneInput.props.onPointerUp(PointerEvent.new("PointerUp",pointer))
        app:Update(1/60)
        Check("人物或部位点击反馈 "..hotspot.id,app.selected==hotspot.id)
        app.ui.closeButton.props.onClick()
        app:Update(1/60)
        app.ui.buttons[hotspot.id].props.onClick()
        app:Update(1/60)
        Check("锚定按钮回调 "..hotspot.id,app.selected==hotspot.id)
        app:Action("close")
        local rect=app.ui.buttons[hotspot.id]:GetAbsoluteLayout()
        if rect.x<0 or rect.y<0 or rect.x+rect.w>w+1 or rect.y+rect.h>h+1 then visible=false end
    end
    Check("热点标签位于屏幕内",visible)
    Check("背景点击不命中",app:Pick(w*0.96,h*0.12)=="")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleMenuAcceptance(eventType,eventData)
    if not app then return end
    frame=frame+1
    app:Update(1/60)
    if frame==30 then
        Check("长直道场景",app.ground.roadLength>=1000 and app.scene:GetChild("LoopRoad",true)==nil)
        Check("无驾驶物理组件",#app.scene:GetComponents("PhysicsWorld",true)==0 and #app.scene:GetComponents("RaycastVehicle",true)==0)
        UI.Layout()
        CheckHotspots()
    elseif frame==120 then
        Check("车辆保持静止",(app.car.worldPosition-initialCar):Length()<0.00001)
        Check("人物占位保持站立",(app.person.worldPosition-initialPerson):Length()<0.00001)
        app:SetFocused(false)
        app:SetFocused(true)
        Check("失焦清理按压状态",next(app.pointerDown)==nil)
        local oldApp=app
        Stop()
        oldApp:Update(1/60)
        oldApp:PostUpdate(1/60)
        oldApp:Shutdown()
        Check("关闭后安全且可重复释放",oldApp.closed and app==nil)
        local passed=true
        for _,item in ipairs(checks) do if not item.passed then passed=false end end
        print("[MENU_REPORT] "..cjson.encode({result=passed and "PASS" or "FAIL",checks=checks}))
    end
end

---@param eventType string
---@param eventData PostUpdateEventData
function HandleMenuAcceptanceCamera(eventType,eventData)
    if app then app:PostUpdate(1/60) end
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    if app then app:Shutdown();app=nil end
end
