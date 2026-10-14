-- 骨架版真实 UI 集成验证：主界面 → 角色准备 → 驾驶舱 → 两轮判定 → 发帖出口。
-- 用"等待条件"驱动而不是固定帧号：场景切换延迟一帧执行，固定帧号容易错位。
-- 每个 Expect 步骤在条件成立时记一条断言；超时未成立则记为失败并打印现场。
-- 只验证流程与输入，不改变正式预览入口；正式参数缺失不影响本验证。
require("main")
local UI = require("urhox-libs/UI")
local GameStart = Start
local checks = 0
local failures = 0
local stepIndex = 0
local waited = 0
local STEP_TIMEOUT = 600

---@class FlowStep
---@field desc string
---@field expect fun(): boolean
---@field act fun()?

---@type FlowStep[]
local steps = {}

local function Check(condition, description)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        log:Write(LOG_ERROR, "[流程集成验证失败] " .. description)
    end
end

local function Text(id)
    local widget = UI.FindById(id)
    if not widget then return "" end
    -- Label 有 GetText；Button 只有 props.text，这里两种都读。
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

-- 点击按钮：直接触发 UI 控件事件，避免依赖坐标命中。
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

---@param desc string
---@param expect fun(): boolean
local function Expect(desc, expect)
    steps[#steps + 1] = { desc = desc, expect = expect, act = nil }
end

---@param desc string
---@param act fun()
local function Act(desc, act)
    -- 动作步骤不等待任何条件：用恒真断言占位，保持类型一致。
    steps[#steps + 1] = { desc = desc, expect = function() return true end, act = act }
end

local function BuildSteps()
    Expect("启动进入主界面", function() return Has("menuStart") end)
    Act("进入角色准备", function() Click("menuStart") end)
    Expect("角色准备列出鞋型", function() return Has("prepShoe2") end)
    Act("选择第二双鞋并确认", function() Click("prepShoe2"); Click("prepConfirm") end)
    Expect("进入驾驶舱", function() return Has("cockpitChance") end)
    Expect("开局机会为 0/3", function() return Text("cockpitChance"):find("0 / 3", 1, true) ~= nil end)
    Expect("开局为第一台车", function() return Text("cockpitVehicle"):find("第 1 台", 1, true) ~= nil end)
    Expect("驾驶舱显示天气", function() return Text("cockpitWeather") ~= "" end)
    Expect("未测试前发帖被禁用", function() return Disabled("cockpitPost") end)

    -- 第 1 次测试：落点按停 → 力度按停。
    Act("第 1 次落点按停", function() Tap(KEY_SPACE) end)
    Expect("进入第二轮力度", function() return Text("demoReading"):find("力度", 1, true) ~= nil end)
    Act("第 1 次力度按停", function() Tap(KEY_SPACE) end)
    Expect("完成一次后机会 1/3", function() return Text("cockpitChance"):find("1 / 3", 1, true) ~= nil end)
    Expect("第一次后可提前发帖", function() return not Disabled("cockpitPost") end)
    Expect("发帖入口提示提前发帖",
        function() return Text("cockpitPost"):find("提前发帖", 1, true) ~= nil end)

    -- 第 2 次测试。
    Act("第 2 次落点按停", function() Tap(KEY_SPACE) end)
    Expect("第 2 次进入力度", function() return Text("demoReading"):find("力度", 1, true) ~= nil end)
    Act("第 2 次力度按停", function() Tap(KEY_SPACE) end)
    Expect("完成两次后机会 2/3", function() return Text("cockpitChance"):find("2 / 3", 1, true) ~= nil end)

    -- 第 3 次测试：结束后必须发帖，离开驾驶舱。
    Act("第 3 次落点按停", function() Tap(KEY_SPACE) end)
    Expect("第 3 次进入力度", function() return Text("demoReading"):find("力度", 1, true) ~= nil end)
    Act("第 3 次力度按停", function() Tap(KEY_SPACE) end)
    Expect("第三次后进入发帖出口", function() return Has("noticeBack") end)
    Expect("已离开驾驶舱", function() return not Has("cockpitChance") end)
    Act("发帖出口返回主界面", function() Click("noticeBack") end)
    Expect("回到主界面", function() return Has("menuStart") end)

    -- 档案页（未实现，只验证可打开与返回）。
    Act("打开档案", function() Click("menuArchive") end)
    Expect("档案页可打开", function() return Has("archiveBack") end)
    Act("档案返回主界面", function() Click("archiveBack") end)
    Expect("档案返回后回到主界面", function() return Has("menuStart") end)

    -- 角色准备可返回主界面。
    Act("再次进入角色准备", function() Click("menuStart") end)
    Expect("角色准备可返回", function() return Has("prepBack") end)
    Act("从角色准备返回主界面", function() Click("prepBack") end)
    Expect("角色准备返回后回到主界面", function() return Has("menuStart") end)
end

function Start()
    GameStart()
    BuildSteps()
    SubscribeToEvent("PostUpdate", "HandleFlowTest")
end

function HandleFlowTest()
    local step = steps[stepIndex + 1]
    if not step then return end
    if step.act then
        step.act()
        stepIndex = stepIndex + 1
        waited = 0
    else
        if step.expect() then
            Check(true, step.desc)
            stepIndex = stepIndex + 1
            waited = 0
        else
            waited = waited + 1
            if waited >= STEP_TIMEOUT then
                Check(false, step.desc .. "（等待超时）")
                print(string.format("[流程集成验证] 超时 步骤=%d/%d 描述=%s 机会=%s",
                    stepIndex + 1, #steps, step.desc, Text("cockpitChance")))
                stepIndex = stepIndex + 1
                waited = 0
            end
        end
    end
    if stepIndex >= #steps then
        print(string.format("[流程集成验证] %s，断言=%d 失败=%d 步骤=%d",
            failures == 0 and "PASS" or "FAIL", checks, failures, stepIndex))
    end
end
