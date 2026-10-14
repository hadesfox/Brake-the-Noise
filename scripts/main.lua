-- 《舆论刹车》开发入口，沿用标准 2D 脚手架的生命周期与新 UI 系统。
-- 当前运行 P1.3f 新设计对齐 Demo（落点/受力重心 → 力度心理曲线）；
-- 正式三幕、完整载荷结算与数值规则尚未启用。
local UI = require("urhox-libs/UI")
local DemoConfig = require("config.Demo")
local GameConfig = require("config.Game")
local Parameters = require("core.Parameters")
local Contracts = require("core.Contracts")
local Landing = require("gameplay.Landing")
local ForceCurve = require("gameplay.ForceCurve")
local Lever = require("gameplay.Lever")
local ContactMapping = require("gameplay.ContactMapping")
local ActionGate = require("core.ActionGate")
local BrakeTestDemo = require("ui.BrakeTestDemo")

local landing = Landing.Create(DemoConfig.landing, DemoConfig.landingSeed)
local force = ForceCurve.Create(DemoConfig.force, DemoConfig.forceSeed)
local gate = ActionGate.Create()
-- 视图由 BrakeTestDemo.Create 创建，生命周期覆盖当前开发测量。
---@type BrakeTestDemoView?
local view = nil
local paused = false
local skipNextUpdate = false
---@type string
local phase = BrakeTestDemo.PHASE_LANDING
---@type integer
local attempt = 0

local function Refresh()
    if view then view:Refresh(landing, force, phase) end
end

-- 两轮共用同一个确认操作。
-- 第一轮沿用作者已确认的 P1.2 手感：先按停锁定落点，此时可同点换鞋比较，再确认进入第二轮。
-- 第二轮按停锁定力度并结束本次测量；结束态再确认开始下一次测量。
local function Confirm(source)
    if paused or not view or not gate:Accept(time:GetFrameNumber()) then return end
    if phase == BrakeTestDemo.PHASE_DONE then
        phase = BrakeTestDemo.PHASE_LANDING
        landing:Resume()
        Refresh()
        return
    end
    if phase == BrakeTestDemo.PHASE_LANDING then
        if landing.moving then
            local record = landing:Lock(source)
            if record then
                local mapping = ContactMapping.Evaluate(DemoConfig.contact,
                    record.pedalCoverage, record.shoeCoverage)
                if record.outcome == "throttle" then
                    print(string.format(
                        "[落点台] 鞋型=%s 鞋中心=(%.6f,%.6f) 结果=throttle 踩到油门 油门交集面积=%.6f 活跃时间=%.3f 来源=%s 配置=%s",
                        record.shoeId, record.x, record.y, record.throttleArea,
                        record.elapsed, source, DemoConfig.version))
                elseif record.hasContact and record.centroidX and record.centroidY then
                    local arm = Lever.Arm(DemoConfig.lever, record.centroidX, record.centroidY)
                    print(string.format(
                        "[落点台] 鞋型=%s 鞋中心=(%.6f,%.6f) 结果=brake 受力重心=(%.6f,%.6f) L=%.4f 距离=%.4f 钳制=%s 面积=%.6f r踏板=%.4f r鞋底=%.4f A集中=%.4f E传导=%.4f A有效=%.4f 活跃时间=%.3f 来源=%s 配置=%s",
                        record.shoeId, record.x, record.y, record.centroidX, record.centroidY,
                        arm.l, arm.distance, tostring(arm.clamped), record.area,
                        record.pedalCoverage, record.shoeCoverage,
                        mapping.concentrate, mapping.conduction, mapping.effective,
                        record.elapsed, source, DemoConfig.version))
                else
                    print(string.format(
                        "[落点台] 鞋型=%s 鞋中心=(%.6f,%.6f) 结果=missed 踩空：无受力重心，不进入载荷计算 活跃时间=%.3f 来源=%s 配置=%s",
                        record.shoeId, record.x, record.y, record.elapsed, source, DemoConfig.version))
                end
            end
        else
            phase = BrakeTestDemo.PHASE_FORCE
            force:Start()
        end
    else
        local record = force:Lock(source)
        if record then
            attempt = attempt + 1
            print(string.format(
                "[力度台] 测量=%d F=%.1fN 意图=%.1fN 停点=%.6f 甜蜜中心=%.6f 甜蜜半宽=%.6f 陡峭=%.3f 暴躁=%.2f 疲劳=%.2f 活跃时间=%.3f 来源=%s 配置=%s",
                attempt, record.force, record.intentForce, record.x, record.sweetCenter,
                record.sweetHalf, record.steepness, record.agitation, record.fatigue,
                record.elapsed, source, DemoConfig.version))
        end
        phase = BrakeTestDemo.PHASE_DONE
    end
    Refresh()
end

-- 第 1 轮按停后可同点换鞋；第 2 轮与结束态不再响应。
local function SelectShoe(index)
    if paused or phase ~= BrakeTestDemo.PHASE_LANDING or landing.moving
        or not view or not gate:Accept(time:GetFrameNumber()) then return end
    if landing:SelectShoe(index) then
        Refresh()
        print("[落点台] 同点换鞋预览=" .. DemoConfig.landing.shoes[index].id .. "；已锁定历史不改写")
    end
end

function Start()
    graphics.windowTitle = DemoConfig.title
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true
    UI.Init({
        theme = "default-taptap",
        scale = UI.Scale.DEFAULT,
        fonts = { { family = "sans", weights = {
            normal = "Fonts/MiSans-Regular.ttf",
            bold = "Fonts/MiSans-Regular.ttf",
        } } },
    })
    view = BrakeTestDemo.Create(DemoConfig.landing, {
        lever = DemoConfig.lever,
        contact = DemoConfig.contact,
        showDebugState = true, -- 开发台显式打开隐藏状态读数；正式局必须关闭。
    }, Confirm, SelectShoe)
    UI.SetRoot(view.root)
    UI.Layout()
    Refresh()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("InputFocus", "HandleInputFocus")
    print("[舆论刹车] P1.3f 新设计对齐台启动，数据契约版本=" .. Contracts.schemaVersion)
    for _, group in ipairs({ "testing", "human", "component" }) do
        local issues = Parameters.Check(GameConfig, group)
        print(string.format("[配置] 分组=%s 正式参数待补=%d 项，仅运行开发几何与曲线 Demo", group, #issues))
        for _, issue in ipairs(issues) do print("[配置] " .. issue) end
    end
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("KeyUp")
    UnsubscribeFromEvent("InputFocus")
    UI.Shutdown()
    view = nil
    gate:ClearHeld()
    print("[舆论刹车] 开发台已清理")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if paused or not view then return end
    if skipNextUpdate then
        skipNextUpdate = false
        return
    end
    local dt = eventData:GetFloat("TimeStep")
    -- 只推进当前阶段，另一轮保持锁定，避免隐藏状态在未开始的那一轮提前生效。
    if phase == BrakeTestDemo.PHASE_LANDING then
        landing:Update(dt)
    elseif phase == BrakeTestDemo.PHASE_FORCE then
        force:Update(dt)
    end
    Refresh()
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")
    if key ~= KEY_SPACE and key ~= KEY_RETURN and key ~= KEY_LEFT and key ~= KEY_RIGHT then return end
    if not gate:Press(key, eventData:GetBool("Repeat")) then return end
    if key == KEY_LEFT or key == KEY_RIGHT then
        local direction = key == KEY_LEFT and -1 or 1
        local index = ((landing.shoeIndex - 1 + direction) % #DemoConfig.landing.shoes) + 1
        SelectShoe(index)
    else
        Confirm("keyboard")
    end
end

---@param eventType string
---@param eventData KeyUpEventData
function HandleKeyUp(eventType, eventData)
    gate:Release(eventData:GetInt("Key"))
end

---@param eventType string
---@param eventData InputFocusEventData
function HandleInputFocus(eventType, eventData)
    paused = not eventData:GetBool("Focus") or eventData:GetBool("Minimized")
    gate:ClearHeld()
    skipNextUpdate = not paused
    if view then view:ShowPaused(paused) end
    print("[开发台] 焦点状态=" .. (paused and "暂停" or "恢复"))
end
