-- 场景展示脚手架的生命周期入口，场地与菜单分别模块化。
local TestGroundApp = require("gameplay.TestGroundApp")
---@type table?
local app

function Start()
    graphics.windowTitle = "山谷试车场 · 实时主界面"
    app = TestGroundApp.Create()
    SubscribeToEvent("Update", "HandleTestGroundUpdate")
    SubscribeToEvent("PostUpdate", "HandleTestGroundCamera")
    SubscribeToEvent("InputFocus", "HandleTestGroundFocus")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleTestGroundUpdate(eventType,eventData)
    if app then app:Update(eventData:GetFloat("TimeStep")) end
end

---@param eventType string
---@param eventData PostUpdateEventData
function HandleTestGroundCamera(eventType,eventData)
    if app then app:PostUpdate(eventData:GetFloat("TimeStep")) end
end

---@param eventType string
---@param eventData InputFocusEventData
function HandleTestGroundFocus(eventType,eventData)
    if app then
        app.focused=eventData:GetBool("Focus") and not eventData:GetBool("Minimized")
        app.accumulator=0
        app.ui:ClearControls()
    end
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("InputFocus")
    if app then app:Shutdown(); app=nil end
end
