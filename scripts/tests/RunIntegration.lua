-- 集成验证入口：在真实 UI 树上验证鼠标/触屏按下、键盘和跨帧锁定。
require("main")
local UI = require("urhox-libs/UI")
local GameStart = Start
local steps = 0
local checks = 0
local failures = 0
local lockedText = ""
local pausedLeft = 0
local pausedLastFrame = 0

local function Check(condition, description)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        log:Write(LOG_ERROR, "[集成验证失败] " .. description)
    end
end

local function Text(id)
    local label = UI.FindById(id) --[[@as Label?]]
    return label and label:GetText() or ""
end

local function Key(down, repeatKey, keyCode)
    local data = VariantMap()
    data["Key"] = Variant(keyCode or KEY_SPACE)
    if down then
        data["Repeat"] = Variant(repeatKey)
        SendEvent("KeyDown", data)
    else
        SendEvent("KeyUp", data)
    end
end

local function Pointer(down, kind, button, targetId)
    local action = UI.FindById(targetId or "demoAction")
    assert(action, "没有确认区")
    UI.Layout()
    local layout = action:GetAbsoluteLayout()
    local scale = UI.Scale.DEFAULT()
    local event = UI.PointerEvent.new(down and "PointerDown" or "PointerUp", {
        pointerId = kind == "mouse" and 0 or 5,
        pointerType = kind, isPrimary = true, button = button,
        x = (layout.x + layout.w / 2) * scale,
        y = (layout.y + layout.h / 2) * scale,
    })
    if down then UI.HandlePointerDown(event) else UI.HandlePointerUp(event) end
end

local function Focus(active)
    local data = VariantMap()
    data["Focus"] = Variant(active)
    data["Minimized"] = Variant(false)
    SendEvent("InputFocus", data)
end

function Start()
    GameStart()
    require("tests.FirstStep").Run()
    SubscribeToEvent("PostUpdate", "HandleIntegrationTest")
end

function HandleIntegrationTest()
    steps = steps + 1
    if steps == 10 then
        UI.Layout()
        Pointer(true, "mouse", MOUSEB_RIGHT)
        Check(Text("demoReading") == "停点  —", "右键不能确认")
        Pointer(false, "mouse", MOUSEB_RIGHT)
        Pointer(true, "mouse", MOUSEB_LEFT)
        Check(Text("demoReading") ~= "停点  —", "鼠标按下立即锁定")
        lockedText = Text("demoReading")
        Key(true, false)
        Check(Text("demoReading") == lockedText, "同帧鼠标加键盘只处理一次")
    elseif steps == 11 then
        Pointer(false, "mouse", MOUSEB_LEFT)
        Check(Text("demoReading") == lockedText, "鼠标抬起不复位")
        Key(true, true)
        Check(Text("demoReading") == lockedText, "长按Repeat不复位")
        Key(false, false)
    elseif steps == 14 then
        Pointer(true, "touch", MOUSEB_LEFT)
        Check(Text("demoReading") == "停点  —", "触屏可开始下一次开发测量")
    elseif steps == 15 then
        Pointer(false, "touch", MOUSEB_LEFT)
        Check(Text("demoReading") == "停点  —", "触屏抬起不锁定")
    elseif steps == 18 then
        Pointer(true, "touch", MOUSEB_LEFT)
        Check(Text("demoReading") ~= "停点  —", "下一次触屏按下有效")
        lockedText = Text("demoReading")
    elseif steps == 19 then
        Pointer(false, "touch", MOUSEB_LEFT)
    elseif steps == 21 then
        Key(true, false)
        Check(Text("demoReading") == "停点  —", "释放后新按键可复位")
        Key(false, false)
    elseif steps == 24 then
        Focus(false)
        local cursor = UI.FindById("demoCursor")
        assert(cursor)
        UI.Layout()
        pausedLeft = cursor:GetLayout().x
        pausedLastFrame = time:GetFrameNumber()
        Check(Text("demoCaption"):find("暂停", 1, true) ~= nil, "失焦进入暂停")
    elseif steps == 28 then
        local cursor = UI.FindById("demoCursor")
        assert(cursor)
        UI.Layout()
        Check(math.abs(cursor:GetLayout().x - pausedLeft) < 0.001, "暂停后游标不移动")
        Focus(true)
    elseif steps == 30 then
        Check(time:GetFrameNumber() > pausedLastFrame, "暂停期间引擎仍推进验证帧")
        Check(Text("demoCaption") == "鞋底移动中", "恢复后回到原状态")
        Key(true, false)
        Check(Text("demoReading") ~= "停点  —", "恢复后可以按停")
        lockedText = Text("demoReading")
        Key(false, false)
    elseif steps == 32 then
        Key(true, false, KEY_RIGHT)
        Key(false, false, KEY_RIGHT)
        Check(Text("demoReading") ~= lockedText, "同点换鞋改变真实面积")
        Check(Text("demoReading"):find("接触面积", 1, true) ~= nil, "显示接触几何读数")
    elseif steps == 34 then
        Key(true, false, KEY_LEFT)
        Key(false, false, KEY_LEFT)
        Check(Text("demoReading") == lockedText, "换回原鞋复现同一落点面积")
    elseif steps == 36 then
        Key(true, false)
        Key(false, false)
        Check(Text("demoReading") == "停点  —", "换鞋后可继续测量")
    elseif steps == 37 then
        Key(true, false, KEY_RIGHT)
        Key(false, false, KEY_RIGHT)
        local button = UI.FindById("shoe2") --[[@as Button?]]
        assert(button)
        Check(button:IsDisabled(), "移动中不能换鞋")
    elseif steps == 40 then
        Key(true, false)
        Key(false, false)
        lockedText = Text("demoReading")
        Check(lockedText ~= "停点  —", "再次测量后能锁定")
    elseif steps == 42 then
        Pointer(true, "touch", MOUSEB_LEFT, "shoe3")
    elseif steps == 43 then
        Pointer(false, "touch", MOUSEB_LEFT, "shoe3")
        Check(Text("demoReading") ~= lockedText, "触屏按钮换成分段鞋产生不同接触面积")
    elseif steps == 45 then
        Pointer(true, "touch", MOUSEB_LEFT, "shoe1")
    elseif steps == 46 then
        Pointer(false, "touch", MOUSEB_LEFT, "shoe1")
        Check(Text("demoReading") == lockedText, "触屏换回宽底复现同点几何")
        print(string.format("[集成验证] %s，断言=%d 失败=%d",
            failures == 0 and "PASS" or "FAIL", checks, failures))
    end
end
