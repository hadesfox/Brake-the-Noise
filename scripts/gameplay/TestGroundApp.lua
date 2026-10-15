-- 基于templates/scaffold-3d-scene.lua：实时试车场主界面，与旧main.lua流程独立。
local MPVPhysics = require("gameplay.MPVPhysics")
local GroundScene = require("gameplay.TestGroundScene")
local GroundUI = require("ui.TestGroundMenu")
local ThirdPersonCamera = require("urhox-libs.Camera.ThirdPersonCamera")
local App = {}
App.__index = App

function App.Create()
    local self = setmetatable({}, App)
    self:Init()
    return self
end

function App:Init()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    self.scene:CreateComponent("DebugRenderer")
    self.physics = self.scene:CreateComponent("PhysicsWorld")
    self.physics.gravity = Vector3(0,-9.81,0)
    self.physics.fps = 120
    self.physics.maxSubSteps = 1
    self.physics.numIterations = 20
    self.physics.interpolation = false
    self.physics.updateEnabled = false
    self.ground = GroundScene.Create(self.scene)
    self.car = MPVPhysics.Create(self.scene)
    self.mode = "menu"
    self.focused = true
    self.pendingAction = ""
    self.controls = {}
    self.cameraIndex = 1
    self.accumulator = 0.0
    self.elapsed = 0.0
    self.distance = 0.0
    self.hudTimer = 0.0
    self.logTimer = 0.0
    self.settleTime = 0.0
    self.steering = 0.0
    self.closed = false
    self.samples = {} ---@type MPVWheelSample[]
    self.lastPosition = Vector3(24,0,0)
    self.menuStart = Vector3(24,0,0)
    self.maxMenuDisplacement = 0.0
    self.camera = ThirdPersonCamera.Create(self.scene, {
        modes = {
            menu={distance=14,offset=Vector3(-2.8,0.9,0),fov=47},
            drive={distance=11,offset=Vector3(0,1.3,0),fov=58},
            overview={distance=62,offset=Vector3.ZERO,fov=52},
        }, initialMode="menu",collisionMask=1,nearClip=0.1,farClip=180,transitionSpeed=4,
    })
    self.overviewTarget = self.scene:CreateChild("OverviewTarget",LOCAL)
    self.overviewTarget.position = Vector3(0,0.5,0)
    self.ui = GroundUI.Create(function(action) self.pendingAction=action end)
    renderer.hdrRendering = true
    renderer:SetNumViewports(1)
    renderer:SetViewport(0,Viewport:new(self.scene,self.camera:GetCamera()))
    input.mouseMode = MM_ABSOLUTE
    self:ResetCar()
    print("[试车场] 实时主界面启动；Enter试驾，W/S油门倒车，A/D转向，空格刹车，R复位，Esc返回")
end

function App:ResetCar()
    self.car:Reset(Vector3(24,0.08,0))
    self.car:SetControls(0,0,120)
    self.lastPosition = self.car:GetModelOrigin()
    self.settleTime = 0
    self.steering = 0
    self.accumulator = 0
    self.samples = {}
    self.ui:ClearControls()
    print("[试车场] 车辆复位到计时门前")
end

function App:Action(action)
    if action == "drive" then
        self.mode="drive"
        self.camera:SetMode("drive")
        self.ui:SetMode("drive")
        self.car:SetControls(0,0,0)
        self.steering=0
        print("[试车场] 菜单 → 手动试驾；同一场景与同一车辆")
    elseif action == "menu" then
        self.mode="menu"
        self.camera:SetMode("menu")
        self.ui:SetMode("menu")
        self:ResetCar()
        print("[试车场] 手动试驾 → 实时主界面")
    elseif action == "overview" then
        self.mode=self.mode == "overview" and "menu" or "overview"
        self.camera:SetMode(self.mode)
        self.ui:SetMode(self.mode)
    elseif action == "camera" then
        self.cameraIndex=self.cameraIndex%3+1
    elseif action == "reset" then
        self:ResetCar()
    end
end

local function Down(key1,key2)
    return input:GetKeyDown(key1) or input:GetKeyDown(key2)
end

function App:ReadInput()
    if input:GetKeyPress(KEY_RETURN) and self.mode ~= "drive" then self:Action("drive") end
    if input:GetKeyPress(KEY_ESCAPE) and self.mode ~= "menu" then self:Action("menu") end
    if input:GetKeyPress(KEY_R) then self:Action("reset") end
    if input:GetKeyPress(KEY_C) then self:Action(self.mode == "drive" and "camera" or "overview") end
    local touch = self.ui:ReadControls()
    self.controls = {
        throttle=Down(KEY_W,KEY_UP) or touch.throttle,
        reverse=Down(KEY_S,KEY_DOWN) or touch.reverse,
        left=Down(KEY_A,KEY_LEFT) or touch.left,
        right=Down(KEY_D,KEY_RIGHT) or touch.right,
        brake=input:GetKeyDown(KEY_SPACE) or touch.brake,
    }
end

function App:AutoControls()
    local p = self.car:GetModelOrigin()
    local radius = math.sqrt(p.x*p.x+p.z*p.z)
    local theta = math.atan(p.z,p.x)
    local lookAhead = theta+0.19
    local target = Vector3(24*math.cos(lookAhead),p.y,24*math.sin(lookAhead))
    local localTarget = self.car.root.worldRotation:Inverse()*(target-p)
    local yawError = math.atan(localTarget.x,localTarget.z)
    -- 0.14量级转向值在本场地实测得到约24m转弯半径；不直接瞬移或指定车身速度。
    local desiredSteer = math.max(-0.42,math.min(0.42,yawError*0.65))
    local speed = self.car.body.linearVelocity:Length()
    local force = math.max(0,math.min(1300,(3.6-speed)*1100))
    local brake = speed > 4.2 and 15 or 0
    if radius < 19 or radius > 29 then
        desiredSteer=math.max(-0.5,math.min(0.5,yawError))
    end
    return force,desiredSteer,brake
end

function App:PhysicsStep(dt)
    self.elapsed=self.elapsed+dt
    self.settleTime=self.settleTime+dt
    local force,desiredSteer,brake=0,0,0
    if self.settleTime < 0.8 then
        brake=120
    elseif self.mode ~= "drive" then
        force,desiredSteer,brake=self:AutoControls()
    else
        local controls = self.controls
        local forward = self.car.root.worldRotation*Vector3.FORWARD
        local signedSpeed = self.car.body.linearVelocity:DotProduct(forward)
        if controls.throttle then
            if signedSpeed < -0.3 then brake=90 else force=1100 end
        elseif controls.reverse then
            if signedSpeed > 0.3 then brake=90 else force=-700 end
        else brake=2 end
        if controls.brake then force=0; brake=160 end
        local steeringInput=(controls.right and 1 or 0)-(controls.left and 1 or 0)
        desiredSteer=steeringInput*0.42
        if math.abs(signedSpeed)>11 then force=0 end
    end
    self.steering=self.steering+(desiredSteer-self.steering)*math.min(1,dt*7)
    self.car:SetControls(force,self.steering,brake)
    self.physics:Update(dt)
    self.samples=self.car:Sample() -- 每步一次，接地状态保存给HUD，不二次查询。
    local p=self.car:GetModelOrigin()
    local traveled=(p-self.lastPosition):Length()
    if traveled<2 then self.distance=self.distance+traveled end
    self.lastPosition=p
    if self.mode ~= "drive" then
        self.maxMenuDisplacement=math.max(self.maxMenuDisplacement,(p-self.menuStart):Length())
    end
    local up=self.car.root.worldRotation*Vector3.UP
    if p.y < -3 or math.abs(p.x)>67 or math.abs(p.z)>67 or up.y<0.15 then
        print("[试车场] 越界或翻车，安全复位")
        self:ResetCar()
    end
end

function App:Update(dt)
    if self.closed then return end
    self.ui:Layout()
    if not self.focused then return end
    if self.pendingAction ~= "" then
        local action=self.pendingAction
        self.pendingAction=""
        self:Action(action)
    end
    self:ReadInput()
    self.accumulator=self.accumulator+math.min(dt,0.10)
    while self.accumulator>=1/120 do
        self.accumulator=self.accumulator-1/120
        self:PhysicsStep(1/120)
    end
    self.ground:Update(self.elapsed)
    self.hudTimer=self.hudTimer+dt
    self.logTimer=self.logTimer+dt
    if self.hudTimer>=0.15 then
        self.hudTimer=0
        local grounded=0
        for _,sample in ipairs(self.samples) do if sample.grounded then grounded=grounded+1 end end
        self.ui:Update(self.car.body.linearVelocity:Length(),grounded,self.distance)
    end
    if self.logTimer>=5 then
        self.logTimer=0
        local p=self.car:GetModelOrigin()
        print(string.format("[试车场状态] mode=%s t=%.1f p=%s speed=%.2f steer=%.3f distance=%.1f menuMotion=%.1f",
            self.mode,self.elapsed,tostring(p),self.car.body.linearVelocity:Length(),self.steering,self.distance,self.maxMenuDisplacement))
    end
end

function App:PostUpdate(dt)
    if self.closed then return end
    local yaw=self.car.root.worldRotation:YawAngle()
    if self.mode == "overview" then
        self.camera:Update(dt,self.overviewTarget,-35,52)
    elseif self.mode == "menu" then
        self.camera:Update(dt,self.car.root,yaw+145+math.sin(self.elapsed*0.12)*7,17)
    else
        local offsets={0,145,-95}
        self.camera:Update(dt,self.car.root,yaw+offsets[self.cameraIndex],16)
    end
end

function App:Shutdown()
    if self.closed then return end
    self.closed=true
    self.focused=false
    self.pendingAction=""
    self.ui:ClearControls()
    self.ui:Shutdown()
    renderer:SetNumViewports(0)
    self.camera:GetNode():Dispose()
    self.scene:Dispose()
    print("[试车场] 已关闭UI、视口与场景")
end

return App
