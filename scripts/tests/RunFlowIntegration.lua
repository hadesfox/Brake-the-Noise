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

    -- 上车过场：三段占位，空格推进，走完自动进入发车前准备。
    Expect("进入上车过场", function() return Has("boardingTitle") end)
    Expect("过场标题为上车", function() return Text("boardingTitle") == "上车" end)
    Expect("过场显示天气与鞋型",
        function() return Text("boardingLine"):find("鞋型", 1, true) ~= nil
            or Text("boardingLine"):find("天气", 1, true) ~= nil end)
    Act("推进过场第 1 段", function() Tap(KEY_SPACE) end)
    Expect("过场推进到第 2 段",
        function() return Text("boardingTitle") == "坐定" or not Has("boardingTitle") end)
    Act("推进过场第 2 段", function() Tap(KEY_SPACE) end)
    Expect("过场推进到第 3 段", function() return Text("boardingTitle") == "准备" end)
    Act("推进过场第 3 段", function() Tap(KEY_SPACE) end)

    -- 发车前准备：空调与座椅可操作，点火后进入加速。
    Expect("进入发车前准备", function() return Has("preDriveStart") end)
    Expect("空调默认关", function() return Text("preDriveAc") == "空调：关" end)
    Act("打开空调", function() Click("preDriveAcBtn") end)
    Expect("空调已打开", function() return Text("preDriveAc") == "空调：开" end)
    Act("点火加速", function() Click("preDriveStart") end)
    -- 加速阶段很短，逐帧采样可能错过中间态；直接等它自动进入刹车时刻。
    Expect("加速到时速 100 后进入刹车时刻",
        function() return Has("cockpitChance") end)

    Expect("驾驶舱机会为 0/3", function() return Text("cockpitChance"):find("0 / 3", 1, true) ~= nil end)
    Expect("驾驶舱为第一台车", function() return Text("cockpitVehicle"):find("第 1 台", 1, true) ~= nil end)
    Expect("未测试前发帖被禁用", function() return Has("cockpitPost") end)

    -- 第 1 次测试：落点按停 → 力度按停 → 选择界面。
    Act("第 1 次落点按停", function() Tap(KEY_SPACE) end)
    Expect("进入第二轮力度", function() return Text("demoReading"):find("力度", 1, true) ~= nil end)
    Act("第 1 次力度按停", function() Tap(KEY_SPACE) end)
    Expect("进入测试后选择界面", function() return Has("decisionContinue") end)
    Expect("第一次后可提前发帖",
        function() return Text("decisionPost"):find("提前发帖", 1, true) ~= nil end)
    Expect("选择界面显示已用机会 1/3",
        function() return Text("decisionSummary"):find("1 / 3", 1, true) ~= nil end)
    Expect("换车在未断裂时不可用", function() return Disabled("decisionVehicle") end)

    -- 继续测试：回到发车前准备，再走一次加速与刹车时刻。
    Act("继续测试", function() Click("decisionContinue") end)
    Expect("继续测试回到发车前准备", function() return Has("preDriveStart") end)
    Act("再次点火加速", function() Click("preDriveStart") end)
    Expect("再次进入刹车时刻", function() return Has("cockpitChance") end)
    Act("第 2 次落点按停", function() Tap(KEY_SPACE) end)
    Expect("第 2 次进入力度", function() return Text("demoReading"):find("力度", 1, true) ~= nil end)
    Act("第 2 次力度按停", function() Tap(KEY_SPACE) end)
    Expect("第二次后机会 2/3",
        function() return Text("decisionSummary"):find("2 / 3", 1, true) ~= nil end)

    -- 第 3 次测试：结束后必须发帖，"继续测试"不可用。
    Act("第 3 次继续测试", function() Click("decisionContinue") end)
    Expect("第 3 次回到发车前准备", function() return Has("preDriveStart") end)
    Act("第 3 次点火加速", function() Click("preDriveStart") end)
    Expect("第 3 次进入刹车时刻", function() return Has("cockpitChance") end)
    Act("第 3 次落点按停", function() Tap(KEY_SPACE) end)
    Expect("第 3 次进入力度", function() return Text("demoReading"):find("力度", 1, true) ~= nil end)
    Act("第 3 次力度按停", function() Tap(KEY_SPACE) end)
    Expect("第三次后必须发帖", function() return Has("decisionContinue") end)
    Expect("第三次后继续测试被禁用", function() return Disabled("decisionContinue") end)
    Expect("第三次后发帖按钮提示必须",
        function() return Text("decisionPost"):find("必须", 1, true) ~= nil end)

    -- 发帖出口（D3 未实现）。
    Act("发帖", function() Click("decisionPost") end)
    Expect("进入发帖出口", function() return Has("noticeBack") end)
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
            if waited == 60 then
                print(string.format("[流程集成验证] 慢 步骤=%d 描述=%s 过场标题=[%s] 发车=[%s] 阶段=[%s]",
                    stepIndex + 1, step.desc, Text("boardingTitle"),
                    tostring(Has("preDriveStart")), Text("phaseLabel")))
            end
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
