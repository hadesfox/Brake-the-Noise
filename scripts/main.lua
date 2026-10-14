-- 《舆论刹车》开发入口，沿用标准 2D 脚手架的生命周期与新 UI 系统。
-- 当前仅运行 P1.1 手感 Demo；正式三幕规则尚未启用。
local UI = require("urhox-libs/UI")
local DemoConfig = require("config.Demo")
local GameConfig = require("config.Game")
local Parameters = require("core.Parameters")
local Contracts = require("core.Contracts")
local Sweep = require("core.Sweep")
local ActionGate = require("core.ActionGate")
local SweepDemo = require("ui.SweepDemo")

local model = Sweep.Create(DemoConfig.sweep.unitsPerSecond, DemoConfig.sweep.initialPhase)
local gate = ActionGate.Create()
---@type table?
local view = nil
local paused = false
local skipNextUpdate = false
---@type integer
local attempt = 0

local function Confirm(source)
    if paused or not view or not gate:Accept(time:GetFrameNumber()) then return end
    -- 只处理输入前的一个状态，禁止同一确认既锁定又复位。
    if model.moving then
        local position = model:Lock()
        attempt = attempt + 1
        view:SetPosition(position)
        view:ShowLocked(position, attempt, source)
        print(string.format("[手感台] 测量=%d 停点=%.6f 活跃时间=%.3f 来源=%s 配置=%s",
            attempt, position, model.elapsed, source, DemoConfig.version))
    else
        -- 从上个停点续测，避免每次复位到相同点影响手感观察。
        model:Resume(model.phase)
        view:ShowMoving()
        print("[手感台] 开始下一次开发测量；不消耗正式游戏机会")
    end
end

function Start()
    graphics.windowTitle = DemoConfig.title
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true
    UI.Init({
        theme = "default-taptap",
        scale = UI.Scale.DEFAULT,
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
                bold = "Fonts/MiSans-Regular.ttf",
            } },
        },
    })
    view = SweepDemo.Create(Confirm)
    UI.SetRoot(view.root)
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("InputFocus", "HandleInputFocus")
    local issues = Parameters.Check(GameConfig, "testing")
    print("[舆论刹车] P1.1 开发手感台启动，数据契约版本=" .. Contracts.schemaVersion)
    print("[配置] 正式参数未启用；待补项目=" .. #issues .. "，仅运行归一化 Demo")
    for _, issue in ipairs(issues) do print("[配置] " .. issue) end
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("KeyUp")
    UnsubscribeFromEvent("InputFocus")
    UI.Shutdown()
    view = nil
    gate:ClearHeld()
    print("[舆论刹车] 手感台已清理")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if paused or not view then return end
    if skipNextUpdate then
        skipNextUpdate = false
        return
    end
    model:Update(eventData:GetFloat("TimeStep"))
    view:SetPosition(model.position)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")
    if key ~= KEY_SPACE and key ~= KEY_RETURN then return end
    if gate:Press(key, eventData:GetBool("Repeat")) then Confirm("keyboard") end
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
    print("[手感台] 焦点状态=" .. (paused and "暂停" or "恢复"))
end
