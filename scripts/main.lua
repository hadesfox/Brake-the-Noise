-- 《舆论刹车》开发入口，沿用标准 2D 脚手架的生命周期与新 UI 系统。
-- 当前运行 P1.2 落点几何 Demo；正式三幕和数值规则尚未启用。
local UI = require("urhox-libs/UI")
local DemoConfig = require("config.Demo")
local GameConfig = require("config.Game")
local Parameters = require("core.Parameters")
local Contracts = require("core.Contracts")
local Landing = require("gameplay.Landing")
local ActionGate = require("core.ActionGate")
local LandingDemo = require("ui.LandingDemo")

local model = Landing.Create(DemoConfig.landing, DemoConfig.landingSeed)
local gate = ActionGate.Create()
-- 视图由 LandingDemo.Create 创建，生命周期覆盖当前开发测量。
---@type LandingDemoView?
local view = nil
local paused = false
local skipNextUpdate = false
---@type integer
local attempt = 0

local function Confirm(source)
    if paused or not view or not gate:Accept(time:GetFrameNumber()) then return end
    -- 一次确认只处理一个状态，锁定记录与后续换鞋预览相互独立。
    if model.moving then
        local record = model:Lock(source)
        if record then
            attempt = attempt + 1
            print(string.format("[落点台] 测量=%d 鞋型=%s 落点=(%.6f,%.6f) 面积=%.6f 活跃时间=%.3f 种子=%d 来源=%s 配置=%s",
                attempt, record.shoeId, record.x, record.y, record.area,
                record.elapsed, record.seed, source, DemoConfig.version))
        end
    else
        model:Resume()
        print("[落点台] 从上次落点续测；历史不清空，不消耗正式游戏机会")
    end
    view:Refresh(model)
end

local function SelectShoe(index)
    if paused or model.moving or not view or not gate:Accept(time:GetFrameNumber()) then return end
    if model:SelectShoe(index) then
        view:Refresh(model)
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
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
                bold = "Fonts/MiSans-Regular.ttf",
            } },
        },
    })
    view = LandingDemo.Create(DemoConfig.landing, Confirm, SelectShoe)
    UI.SetRoot(view.root)
    UI.Layout()
    view:Refresh(model)
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("InputFocus", "HandleInputFocus")
    local issues = Parameters.Check(GameConfig, "testing")
    print("[舆论刹车] P1.2 落点几何台启动，数据契约版本=" .. Contracts.schemaVersion)
    print("[配置] 正式参数未启用；待补项目=" .. #issues .. "，仅运行开发几何 Demo")
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
    view:Refresh(model)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")
    if key ~= KEY_SPACE and key ~= KEY_RETURN and key ~= KEY_LEFT and key ~= KEY_RIGHT then return end
    if not gate:Press(key, eventData:GetBool("Repeat")) then return end
    if key == KEY_LEFT or key == KEY_RIGHT then
        local direction = key == KEY_LEFT and -1 or 1
        local index = ((model.shoeIndex - 1 + direction) % #DemoConfig.landing.shoes) + 1
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
    print("[手感台] 焦点状态=" .. (paused and "暂停" or "恢复"))
end
