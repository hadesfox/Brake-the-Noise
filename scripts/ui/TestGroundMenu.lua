-- 主界面仅保留场景热点与占位反馈，不制作驾驶HUD或未确认的功能页。
local UI=require("urhox-libs/UI")
local Menu={}
Menu.__index=Menu

function Menu.Create(hotspots,onAction,onPointer)
    local self=setmetatable({},Menu)
    self:Init(hotspots,onAction,onPointer)
    return self
end

function Menu:Init(hotspots,onAction,onPointer)
    local theme=UI.Theme.ExtendTheme(UI.Theme.defaultTheme,{
        colors={primary={225,157,70,255},primaryHover={244,181,103,255},primaryPressed={182,125,52,255},
            secondary={43,64,61,255},secondaryHover={67,93,84,255},secondaryPressed={29,46,43,255},
            text={242,239,222,255},textSecondary={185,194,181,255}},
        components={Button={height=42,borderRadius=3,fontSize=12}},
    })
    UI.Init({theme=theme,scale=UI.Scale.DEFAULT,
        fonts={{family="sans",weights={normal="Fonts/MiSans-Regular.ttf"}}}})
    self.hotspots=hotspots
    self.onAction=onAction
    self.buttons={} ---@type table<string,Button>
    self.dots={} ---@type table<string,Panel>
    self.hover=""
    self.selected=""
    self.feedbackTitle=UI.Label{text="",fontSize=15,fontColor={242,239,222,255}}
    self.feedbackText=UI.Label{text="",fontSize=11,whiteSpace="normal",fontColor={185,194,181,255}}
    self.closeButton=UI.Button{text="收起",variant="secondary",width=76,onClick=function()self.onAction("close")end}
    self.feedback=UI.Panel{position="absolute",bottom=18,left=18,width=310,maxWidth="90%",padding=14,gap=8,
        backgroundColor={24,34,32,238},visible=false,children={self.feedbackTitle,self.feedbackText,self.closeButton}}
    self.header=UI.Panel{position="absolute",top=20,left=24,pointerEvents="none",gap=4,children={
        UI.Label{text="舆论刹车",fontSize=26,fontColor={38,53,49,255}},
        UI.Label{text="零百加速直道 · 主界面构图",fontSize=11,fontColor={58,73,67,255}},
    }}
    self.hint=UI.Label{text="点击人物、车门或车尾 · 当前仅演示主界面入口",fontSize=11,
        position="absolute",bottom=18,left=24,fontColor={235,234,218,255}}
    self.sceneInput=UI.Panel{width="100%",height="100%",position="absolute",left=0,top=0,
        onPointerDown=function(event)onPointer(event,"down")end,
        onPointerUp=function(event)onPointer(event,"up")end,
        onPointerMove=function(event)onPointer(event,"move")end,
        onPointerCancel=function(event)onPointer(event,"cancel")end}
    self.overlay=UI.Panel{width="100%",height="100%",position="absolute",left=0,top=0,pointerEvents="box-none"}
    for _,hotspot in ipairs(hotspots) do
        local id=hotspot.id
        local dot=UI.Panel{position="absolute",width=7,height=7,borderRadius=4,
            backgroundColor={235,170,82,255},pointerEvents="none"}
        local button=UI.Button{text=hotspot.title,variant="secondary",width=128,height=42,
            position="absolute",left=0,top=0,borderWidth=1,borderColor={197,211,188,130},
            onClick=function()self.onAction(id)end,
            onPointerEnter=function()self:SetHover(id)end,
            onPointerLeave=function()self:SetHover("")end}
        self.buttons[id]=button
        self.dots[id]=dot
        self.overlay:AddChild(dot)
        self.overlay:AddChild(button)
    end
    UI.SetRoot(UI.Panel{width="100%",height="100%",children={self.sceneInput,self.overlay,
        UI.SafeAreaView{width="100%",height="100%",nativeMenuInset=true,pointerEvents="box-none",
            children={self.header,self.hint,self.feedback}},
    }})
    UI.Layout()
end

function Menu:GetViewportSize()
    return UI.GetViewportSize()
end

function Menu:UpdateAnchors(camera)
    local width,height=UI.GetViewportSize()
    local safeX,safeY,safeWidth,safeHeight=UI.GetSafeContentArea()
    local small=height<560
    self.header:SetStyle({top=small and 12 or 20,left=small and 16 or 24})
    local used={} ---@type table[]
    for _,hotspot in ipairs(self.hotspots) do
        local screen=camera:WorldToScreenPoint(hotspot.node:LocalToWorld(hotspot.anchor))
        local x,y=screen.x*width,screen.y*height
        local left=math.max(safeX+12,math.min(safeX+safeWidth-140,x+hotspot.offset.x))
        local top=math.max(safeY+96,math.min(safeY+safeHeight-82,y+hotspot.offset.y))
        for _,rect in ipairs(used) do
            if math.abs(left-rect.x)<136 and math.abs(top-rect.y)<48 then top=math.min(top+52,safeY+safeHeight-70) end
        end
        used[#used+1]={x=left,y=top}
        self.buttons[hotspot.id]:SetStyle({left=left,top=top})
        self.dots[hotspot.id]:SetStyle({left=x-3.5,top=y-3.5})
    end
    self.hint:SetVisible(self.selected=="")
    self.hint:SetText(width<600 and "点击人物或车辆部位" or "点击人物、车门或车尾 · 当前仅演示主界面入口")
end

function Menu:SetHover(id)
    if self.hover==id then return end
    self.hover=id
    for key,button in pairs(self.buttons) do
        button:SetStyle({borderColor=key==id and {235,170,82,255} or {197,211,188,130}})
    end
end

function Menu:ShowSelection(id)
    self.selected=id
    local title=""
    for _,hotspot in ipairs(self.hotspots) do if hotspot.id==id then title=hotspot.title end end
    self.feedbackTitle:SetText(title)
    self.feedbackText:SetText(id=="person" and "人物为灰色占位。本轮不确定外形，也不进入人物制作。" or
        "入口已选中，当前仅为主界面交互占位，不启动测试或档案流程。")
    self.feedback:SetVisible(true)
    self.hint:SetVisible(false)
end

function Menu:CloseSelection()
    self.selected=""
    self.feedback:SetVisible(false)
    self.hint:SetVisible(true)
end

function Menu:Shutdown()
    UI.Shutdown()
end

return Menu
