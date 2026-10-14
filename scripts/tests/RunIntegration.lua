-- 集成验证入口：在真实 UI 树上验证鼠标/触屏按下、键盘、两轮切换与跨帧锁定。
-- 第一轮沿用作者已确认的 P1.2 手感：按停 → 可同点换鞋 → 再确认进入第二轮。
-- 确认与换鞋共用同一个按帧去重的 ActionGate，因此每个验证帧只做一次动作。
require("main")
local UI = require("urhox-libs/UI")
local GameStart = Start
local steps = 0
local checks = 0
local failures = 0
local lockedText = ""
local pausedLeft = 0
local pausedLastFrame = 0

local PHASE_LANDING = "第 1 轮 · 落点与接触面"
local PHASE_FORCE = "第 2 轮 · 力度"
local PHASE_DONE = "本轮两轮判定已结束"

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

local function Phase()
    return Text("phaseLabel")
end

local function ShoeDisabled(id)
    local button = UI.FindById(id) --[[@as Button?]]
    assert(button, "找不到鞋型按钮")
    return button:IsDisabled()
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

local function Tap(keyCode)
    Key(true, false, keyCode)
    Key(false, false, keyCode)
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
        Check(Phase() == PHASE_LANDING, "启动进入第 1 轮")
        Pointer(true, "mouse", MOUSEB_RIGHT)
        Check(Text("demoReading") == "停点  —", "右键不能确认")
        Pointer(false, "mouse", MOUSEB_RIGHT)
        Pointer(true, "mouse", MOUSEB_LEFT)
        Check(Text("demoReading") ~= "停点  —", "鼠标按下锁定落点")
        lockedText = Text("demoReading")
        Key(true, false)
        Check(Text("demoReading") == lockedText, "同帧鼠标加键盘只处理一次")
    elseif steps == 11 then
        Pointer(false, "mouse", MOUSEB_LEFT)
        Check(Text("demoReading") == lockedText, "鼠标抬起不重复处理")
        Key(true, true)
        Check(Text("demoReading") == lockedText, "长按Repeat不重复处理")
        Key(false, false)
    elseif steps == 12 then
        Tap(KEY_RIGHT)
        Check(Text("demoReading") ~= lockedText, "锁定后同点换鞋改变真实面积")
        Check(Text("demoReading"):find("接触面积", 1, true) ~= nil, "显示接触几何读数")
    elseif steps == 13 then
        Tap(KEY_LEFT)
        Check(Text("demoReading") == lockedText, "换回原鞋复现同一落点面积")
    elseif steps == 14 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_FORCE, "第二次确认进入第 2 轮")
        Check(Text("demoReading"):find("力度", 1, true) ~= nil, "第 2 轮显示力度读数")
    elseif steps == 15 then
        Check(ShoeDisabled("shoe2"), "第 2 轮鞋型按钮不可用")
        Tap(KEY_RIGHT)
        Check(Phase() == PHASE_FORCE, "第 2 轮不接受换鞋")
    elseif steps == 16 then
        Pointer(true, "touch", MOUSEB_LEFT)
        Check(Phase() == PHASE_DONE, "触屏完成第 2 轮")
        lockedText = Text("demoReading")
        Check(lockedText:find("甜蜜点", 1, true) ~= nil, "锁定后给出甜蜜点与低平区")
    elseif steps == 17 then
        Pointer(false, "touch", MOUSEB_LEFT)
        Check(Phase() == PHASE_DONE, "触屏抬起不重复推进")
    elseif steps == 18 then
        Check(ShoeDisabled("shoe2"), "结束态鞋型按钮不可用")
        Tap(KEY_RIGHT)
        Check(Text("demoReading") == lockedText, "结束态不接受换鞋")
    elseif steps == 20 then
        Pointer(true, "touch", MOUSEB_LEFT)
        Check(Phase() == PHASE_LANDING, "结束态再确认开始下一次测量")
        -- 新一轮刚开跑，鞋型按钮应当因为"移动中"而禁用，等按停后才恢复。
        Check(ShoeDisabled("shoe2"), "新一轮移动中鞋型按钮禁用")
    elseif steps == 21 then
        Pointer(false, "touch", MOUSEB_LEFT)
    elseif steps == 22 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_LANDING and not ShoeDisabled("shoe2"), "按停后鞋型按钮重新可用")
    elseif steps == 23 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_FORCE, "再确认进入第 2 轮")
    elseif steps == 24 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_DONE, "完成第 2 轮回到结束态")
    elseif steps == 25 then
        Focus(false)
        local cursor = UI.FindById("demoCursor")
        assert(cursor)
        UI.Layout()
        pausedLeft = cursor:GetLayout().x
        pausedLastFrame = time:GetFrameNumber()
        Check(Text("demoCaption"):find("暂停", 1, true) ~= nil, "失焦进入暂停")
    elseif steps == 29 then
        local cursor = UI.FindById("demoCursor")
        assert(cursor)
        UI.Layout()
        Check(math.abs(cursor:GetLayout().x - pausedLeft) < 0.001, "暂停后游标不移动")
        Focus(true)
    elseif steps == 31 then
        Check(time:GetFrameNumber() > pausedLastFrame, "暂停期间引擎仍推进验证帧")
        Check(Phase() == PHASE_DONE, "恢复后回到原状态")
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_LANDING, "恢复后可以重新开始测量")
    elseif steps == 32 then
        Tap(KEY_SPACE)
        Check(Text("demoReading") ~= "停点  —", "恢复后可以按停")
    elseif steps == 33 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_FORCE, "恢复后可进入第 2 轮")
    elseif steps == 34 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_DONE, "恢复后可完成第 2 轮")
        lockedText = Text("demoReading")
    elseif steps == 35 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_LANDING, "再次开始新测量")
    elseif steps == 36 then
        Tap(KEY_SPACE)
        Check(Text("demoReading") ~= "停点  —", "第 1 轮再次按停")
    elseif steps == 37 then
        Tap(KEY_RIGHT)
        Check(Phase() == PHASE_LANDING, "第 1 轮锁定后仍可换鞋")
    elseif steps == 38 then
        Tap(KEY_SPACE)
        Check(Phase() == PHASE_FORCE, "换鞋后进入第 2 轮")
    elseif steps == 39 then
        Pointer(true, "touch", MOUSEB_LEFT)
        Check(Phase() == PHASE_DONE, "触屏完成第 2 轮")
        Check(Text("demoReading") ~= lockedText, "新一次测量给出新力度")
        Pointer(false, "touch", MOUSEB_LEFT)
        print(string.format("[集成验证] %s，断言=%d 失败=%d",
            failures == 0 and "PASS" or "FAIL", checks, failures))
    end
end
