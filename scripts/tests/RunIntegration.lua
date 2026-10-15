-- 两轮判定的输入细节集成验证（骨架版入口）。
--
-- 正式流程：落点一次确认 → 力度一次确认；换鞋在角色准备阶段完成，测试中不换鞋。
-- 这里验证输入边界：右键过滤、同帧去重、长按不重复、暂停不响应、触屏路径。
-- 会话机会与发帖门槛由 RunFlowIntegration 覆盖；几何读数由纯逻辑测试覆盖。
--
-- 注意：每个 Step 在不同的 PostUpdate 帧执行，所以"同帧去重"必须在一个 Step 内
-- 连续发送两个输入；拆成两步就是两个合法帧，第二个输入会真的生效。
require("main")
local UI = require("urhox-libs/UI")
local GameStart = Start
local checks = 0
local failures = 0
local stepIndex = 0
local waited = 0
local STEP_TIMEOUT = 600

---@class DetailStep
---@field desc string
---@field run fun(): boolean 返回 true 表示本步完成

---@type DetailStep[]
local steps = {}

local function Check(condition, description)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        log:Write(LOG_ERROR, "[集成验证失败] " .. description)
    end
end

local function Text(id)
    local widget = UI.FindById(id)
    if not widget then return "" end
    local getter = widget.GetText
    if getter then return getter(widget) end
    local props = widget.props
    if props and type(props.text) == "string" then return props.text end
    return ""
end

local function Has(id)
    return UI.FindById(id) ~= nil
end

local function Disabled(id)
    local button = UI.FindById(id) --[[@as Button?]]
    assert(button, "找不到按钮 " .. id)
    return button:IsDisabled()
end

local function Click(id)
    local widget = UI.FindById(id)
    assert(widget, "找不到可点控件 " .. id)
    UI.Layout()
    local layout = widget:GetAbsoluteLayout()
    local scale = UI.Scale.DEFAULT()
    local x = (layout.x + layout.w / 2) * scale
    local y = (layout.y + layout.h / 2) * scale
    UI.HandlePointerDown(UI.PointerEvent.new("PointerDown", {
        pointerId = 0, pointerType = "mouse", isPrimary = true, button = MOUSEB_LEFT, x = x, y = y,
    }))
    UI.HandlePointerUp(UI.PointerEvent.new("PointerUp", {
        pointerId = 0, pointerType = "mouse", isPrimary = true, button = MOUSEB_LEFT, x = x, y = y,
    }))
end

local function KeyDown(repeatKey, keyCode)
    local data = VariantMap()
    data["Key"] = Variant(keyCode or KEY_SPACE)
    data["Repeat"] = Variant(repeatKey)
    SendEvent("KeyDown", data)
end

local function KeyUp(keyCode)
    local data = VariantMap()
    data["Key"] = Variant(keyCode or KEY_SPACE)
    SendEvent("KeyUp", data)
end

local function Tap(keyCode)
    KeyDown(false, keyCode)
    KeyUp(keyCode)
end

-- 在确认区上模拟一次指针事件，用于验证右键过滤与触屏路径。
local function Pointer(down, kind, button)
    local action = UI.FindById("demoAction")
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

local function InLanding()
    return Text("phaseLabel"):find("第 1 轮", 1, true) ~= nil
end

local function InForce()
    return Text("phaseLabel"):find("第 2 轮", 1, true) ~= nil
end

local function Chance()
    return Text("cockpitChance")
end

local function ChanceCount()
    return tonumber(Chance():match("(%d+)%s*/"))
end

---@param desc string
---@param run fun(): boolean
local function Step(desc, run)
    steps[#steps + 1] = { desc = desc, run = run }
end

local function BuildSteps()
    Step("进入驾驶舱", function()
        if Has("menuStart") then Click("menuStart") return false end
        if Has("prepConfirm") then Click("prepConfirm") return false end
        -- 上车过场：连按空格推进；走完会自动切到发车前准备。
        if Has("boardingTitle") then
            Tap(KEY_SPACE)
            return false
        end
        if Has("preDriveStart") then Click("preDriveStart") return false end
        return Has("cockpitChance")
    end)
    Step("开局为落点轮且机会 0/3", function()
        Check(InLanding(), "开局为落点轮")
        Check(ChanceCount() == 0, "开局机会 0/3")
        return true
    end)
    Step("正式流程不显示测试中换鞋", function()
        local shoeRow = UI.FindById("shoeRow")
        Check(shoeRow == nil or not shoeRow:IsVisible(), "正式流程不显示测试中换鞋")
        return true
    end)
    Step("右键不能确认", function()
        Pointer(true, "mouse", MOUSEB_RIGHT)
        Check(InLanding() and Text("demoReading") == "停点  —", "右键不能确认")
        Pointer(false, "mouse", MOUSEB_RIGHT)
        return true
    end)
    Step("左键一次确认进入力度轮", function()
        Pointer(true, "mouse", MOUSEB_LEFT)
        Check(InForce(), "左键一次确认进入力度轮")
        Check(ChanceCount() == 0, "落点确认本身不占用机会")
        return true
    end)
    Step("鼠标抬起不重复推进", function()
        Pointer(false, "mouse", MOUSEB_LEFT)
        Check(InForce(), "鼠标抬起不重复推进")
        return true
    end)
    -- 同帧去重：同一帧内先触屏锁定力度，再按键盘；第二次必须被 ActionGate 拒绝。
    Step("同帧触屏加键盘只结算一次", function()
        Pointer(true, "touch", MOUSEB_LEFT)
        Check(Has("decisionContinue"), "触屏锁定力度结算一次")
        Check(Text("decisionSummary"):find("1 / 3", 1, true) ~= nil, "同帧触屏只记一次机会")
        KeyDown(false)
        Check(Text("decisionSummary"):find("1 / 3", 1, true) ~= nil, "同帧键盘没有重复结算")
        KeyUp()
        Pointer(false, "touch", MOUSEB_LEFT)
        return true
    end)
    Step("结算后进入选择界面", function()
        Check(Has("decisionContinue"), "结算后进入选择界面")
        Check(Text("decisionSummary"):find("1 / 3", 1, true) ~= nil, "完成一次后机会 1/3")
        return true
    end)
    Step("长按 Repeat 不重复结算", function()
        -- 选择界面上长按空格不应重复触发任何动作。
        KeyDown(true)
        Check(Has("decisionContinue"), "长按 Repeat 不重复结算")
        KeyUp()
        return true
    end)
    Step("回到发车前准备再测一次", function()
        if Has("preDriveStart") then return true end
        if Has("decisionContinue") then
            Click("decisionContinue")
            return false
        end
        return Has("cockpitChance")
    end)
    Step("点火加速回到刹车时刻", function()
        if Has("preDriveStart") then
            Click("preDriveStart")
            return false
        end
        return Has("cockpitChance")
    end)
    Step("失焦进入暂停", function()
        Focus(false)
        return Text("demoCaption"):find("暂停", 1, true) ~= nil
    end)
    Step("暂停期间不响应确认", function()
        Tap(KEY_SPACE)
        Check(InLanding(), "暂停期间不响应确认")
        return true
    end)
    Step("恢复后仍可继续", function()
        Focus(true)
        return InLanding()
    end)
    -- 一次测试结束后进入独立选择界面；"继续测试"要重新走发车前准备与加速。
    -- 落点确认与力度确认必须在不同帧：它们各自占一次 ActionGate 帧号。
    Step("第 2 次落点确认", function()
        if not InLanding() then return false end
        Tap(KEY_SPACE)
        return InForce()
    end)
    Step("第 2 次力度结算", function()
        Tap(KEY_SPACE)
        return Has("decisionContinue")
    end)
    Step("第二次后机会 2/3", function()
        Check(Text("decisionSummary"):find("2 / 3", 1, true) ~= nil, "完成第 2 次后机会 2/3")
        return true
    end)
    Step("继续测试回到发车前准备", function()
        if Has("preDriveStart") then return true end
        Click("decisionContinue")
        return Has("preDriveStart")
    end)
    Step("第 3 次点火加速", function()
        if Has("preDriveStart") then
            Click("preDriveStart")
            return false
        end
        return Has("cockpitChance")
    end)
    Step("第 3 次落点确认", function()
        if not InLanding() then return false end
        Tap(KEY_SPACE)
        return InForce()
    end)
    Step("第 3 次力度结算", function()
        Tap(KEY_SPACE)
        return Has("decisionContinue")
    end)
    Step("第三次后继续测试被禁用", function()
        Check(Disabled("decisionContinue"), "第三次后继续测试被禁用")
        return true
    end)
    Step("发帖进入出口", function()
        if Has("decisionPost") then
            Click("decisionPost")
            return false
        end
        return Has("noticeBack")
    end)
    Step("发帖出口已离开驾驶舱", function()
        Check(not Has("cockpitChance"), "发帖出口已离开驾驶舱")
        return true
    end)
end

function Start()
    GameStart()
    BuildSteps()
    SubscribeToEvent("PostUpdate", "HandleDetailTest")
end

function HandleDetailTest()
    local step = steps[stepIndex + 1]
    if not step then return end
    if step.run() then
        stepIndex = stepIndex + 1
        waited = 0
    else
        waited = waited + 1
        if waited >= STEP_TIMEOUT then
            Check(false, step.desc .. "（等待超时）")
            print(string.format("[集成验证] 超时 步骤=%d/%d 描述=%s 阶段=%s 机会=%s",
                stepIndex + 1, #steps, step.desc, Text("phaseLabel"), Chance()))
            stepIndex = stepIndex + 1
            waited = 0
        end
    end
    if stepIndex >= #steps then
        print(string.format("[集成验证] %s，断言=%d 失败=%d 步骤=%d",
            failures == 0 and "PASS" or "FAIL", checks, failures, stepIndex))
    end
end
