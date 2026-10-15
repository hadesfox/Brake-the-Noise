-- 实时主界面与试驾HUD，使用UI组件，不额外建立NanoVG渲染管线。
local UI = require("urhox-libs/UI")
local GroundUI = {}
GroundUI.__index = GroundUI

function GroundUI.Create(onAction)
    local self = setmetatable({}, GroundUI)
    self:Init(onAction)
    return self
end

function GroundUI:Init(onAction)
    -- 在查阅预置风格后沿用基础主题结构，配色匹配低模山谷与道路警示色。
    local theme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        colors = {
            primary = {229,155,66,255}, primaryHover = {247,178,90,255}, primaryPressed = {194,123,44,255},
            secondary = {53,91,85,255}, secondaryHover = {69,112,104,255}, secondaryPressed = {36,66,61,255},
            background = {22,32,31,255}, surface = {32,45,43,244}, text = {241,237,214,255},
            textSecondary = {180,195,177,255}, border = {104,128,111,100},
        },
        components = { Button = { height = 48, borderRadius = 4, fontSize = 14 }, Label = { fontFamily = "sans" } },
    })
    UI.Init({ theme = theme, scale = UI.Scale.DEFAULT,
        fonts = {{family="sans",weights={normal="Fonts/MiSans-Regular.ttf",bold="Fonts/MiSans-Regular.ttf"}}} })
    self.onAction = onAction
    self.mode = "menu"
    self.detail = UI.Label { text = "真实场景 · 自动巡航", fontSize = 11, fontColor = {180,195,177,255} }
    self.speed = UI.Label { text = "00", fontSize = 36, fontColor = {241,237,214,255} }
    self.status = UI.Label { text = "正在驶入测试场", fontSize = 12, fontColor = {180,195,177,255} }
    self.startButton = UI.Button { text = "开始试驾  →", width = "100%", textColor = {26,35,30,255},
        onClick = function() self.onAction("drive") end }
    self.overviewButton = UI.Button { text = "场地全景", variant = "secondary", width = "100%",
        onClick = function() self.onAction("overview") end }
    self.title = UI.Label {text="山谷试车场",fontSize=30,fontColor={241,237,214,255}}
    self.tagline = UI.Label {text="把路，开成你的主界面。",fontSize=13,fontColor={180,195,177,255}}
    self.divider = UI.Panel {height=1,backgroundColor={104,128,111,90},marginVertical=3}
    self.features = UI.Label {text="环形道路 / 减速带 / 悬挂坡 / 防撞区",fontSize=10,
        whiteSpace="normal",fontColor={180,195,177,255}}
    self.shortcuts = UI.Label {text="Enter 试驾 · C 视角 · Esc 返回",fontSize=10,fontColor={142,163,147,255}}
    self.menu = UI.Panel {
        position="absolute", left=28, top="14%", width=330, maxWidth="43%", padding=22, gap=14,
        backgroundColor={22,32,31,234}, borderLeftWidth=3, borderLeftColor={229,155,66,255},
        children={
            UI.Label{text="MPV / PROVING GROUND",fontSize=10,fontColor={229,155,66,255}},
            self.title,self.tagline,self.divider,self.detail,self.startButton,self.overviewButton,
            self.features,self.shortcuts,
        },
    }
    self.returnButton = UI.Button {text="返回主界面",variant="secondary",onClick=function()self.onAction("menu")end}
    self.resetButton = UI.Button {text="复位车辆",variant="secondary",onClick=function()self.onAction("reset")end}
    self.cameraButton = UI.Button {text="切换视角",variant="secondary",onClick=function()self.onAction("camera")end}
    self.driveBar = UI.Panel {
        position="absolute",top=18,left=18,right=18,flexDirection="row",gap=8,visible=false,pointerEvents="box-none",
        children={self.returnButton,self.resetButton,self.cameraButton},
    }
    self.throttle = UI.Button{text="加速",width=76,height=56}
    self.reverse = UI.Button{text="倒车",variant="secondary",width=76,height=56}
    self.left = UI.Button{text="←",variant="secondary",width=64,height=56}
    self.right = UI.Button{text="→",variant="secondary",width=64,height=56}
    self.brake = UI.Button{text="刹车",variant="secondary",width=76,height=56}
    self.controls = UI.Panel {
        position="absolute",bottom=20,left=20,right=20,flexDirection="row",justifyContent="space-between",
        visible=false,pointerEvents="box-none",children={
            UI.Panel{flexDirection="row",gap=8,children={self.left,self.right}},
            UI.Panel{flexDirection="row",gap=8,children={self.reverse,self.brake,self.throttle}},
        },
    }
    self.telemetry = UI.Panel {
        position="absolute",right=24,top=24,width=175,padding=14,gap=4,backgroundColor={22,32,31,220},
        pointerEvents="none",children={
            UI.Label{text="LIVE / 实时车辆",fontSize=10,fontColor={229,155,66,255}},
            UI.Panel{flexDirection="row",alignItems="baseline",gap=6,children={self.speed,
                UI.Label{text="km/h",fontSize=11,fontColor={180,195,177,255}}}},self.status,
        },
    }
    self.footer = UI.Label{text="01  山谷试车场     /     七座 MPV     /     1800 kg 测试配置",fontSize=10,
        position="absolute",bottom=20,left=28,fontColor={241,237,214,255}}
    UI.SetRoot(UI.Panel{width="100%",height="100%",pointerEvents="box-none",children={
        UI.SafeAreaView{width="100%",height="100%",nativeMenuInset=true,pointerEvents="box-none",
            children={self.menu,self.driveBar,self.controls,self.telemetry,self.footer}},
    }})
    self.layoutWidth=0.0
    self.layoutHeight=0.0
    UI.Layout()
    self:Layout()
end

function GroundUI:Layout()
    -- 使用UI基准像素与安全区，不用物理分辨率判断紧凑模式。
    local _,_,width,height=UI.GetSafeContentArea()
    if width==self.layoutWidth and height==self.layoutHeight then return end
    self.layoutWidth=width
    self.layoutHeight=height
    local portrait=width<height
    local compact=height<620 or width<760
    local menuWidth=portrait and math.min(330,width-32) or math.min(330,width*0.43)
    self.menu:SetStyle({left=compact and 16 or 28,width=menuWidth,maxWidth="100%",
        top=portrait and YGUndefined or (compact and 20 or "14%"),
        bottom=portrait and 16 or YGUndefined,padding=compact and 16 or 22,gap=compact and 10 or 14})
    self.title:SetFontSize(compact and 24 or 30)
    self.tagline:SetVisible(not compact)
    self.divider:SetVisible(not compact)
    self.shortcuts:SetVisible(not compact)
    self.features:SetVisible(not compact or height>=500)
    self.footer:SetVisible(not compact and self.mode~="drive")
    self.telemetry:SetStyle({right=compact and 16 or 24,width=compact and 165 or 175})
    self.driveBar:SetStyle({left=12,right=12})
    for _,button in ipairs({self.returnButton,self.resetButton,self.cameraButton}) do
        button:SetStyle({flexGrow=1,flexBasis=0,flexShrink=1,minWidth=0,fontSize=compact and 12 or 14})
    end
    self.controls:SetStyle({left=12,right=12})
    for _,button in ipairs({self.left,self.right}) do button:SetWidth(width<480 and 54 or 64) end
    for _,button in ipairs({self.reverse,self.brake,self.throttle}) do button:SetWidth(width<480 and 58 or 76) end
end

function GroundUI:ClearControls()
    for _,button in ipairs({self.throttle,self.reverse,self.left,self.right,self.brake}) do
        button:SetState({pressed=false})
    end
end

function GroundUI:SetMode(mode)
    self:ClearControls()
    self.mode = mode
    local driving = mode == "drive"
    self.menu:SetVisible(not driving)
    self.driveBar:SetVisible(driving)
    self.controls:SetVisible(driving)
    self.footer:SetVisible(not driving)
    self.telemetry:SetStyle({top=driving and 82 or 24})
    self.overviewButton:SetText(mode == "overview" and "返回车辆近景" or "场地全景")
    self.layoutWidth=0
    self:Layout()
end

function GroundUI:ReadControls()
    return {
        throttle = self.throttle.state.pressed == true,
        reverse = self.reverse.state.pressed == true,
        left = self.left.state.pressed == true,
        right = self.right.state.pressed == true,
        brake = self.brake.state.pressed == true,
    }
end

function GroundUI:Update(speed, grounded, distance)
    self.speed:SetText(string.format("%02d",math.floor(speed*3.6+0.5)))
    self.status:SetText(string.format("接地 %d/4 · %.0f m",grounded,distance))
    self.detail:SetText(self.mode == "overview" and "场地全景 · 车辆仍在真实运行" or "实时场景 · 车辆正在自动巡航")
end

function GroundUI:Shutdown()
    UI.Shutdown()
end

return GroundUI
