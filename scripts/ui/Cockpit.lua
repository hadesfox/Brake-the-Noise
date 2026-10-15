-- 驾驶舱页面（骨架版）。第一人称驾驶舱的正式美术未到位，这里只搭结构与流程：
--   · 窗外天气条：只做氛围与记录，天气对隐藏状态的作用等待正式参数。
--   · 会话 HUD：总机会 x/3、当前车辆、当前鞋型；不显示任何隐藏状态数字。
--   · 复用 ui/BrakeTestDemo 的测试区（embedded 模式），保证画面与判定几何同源。
--   · 底部流程动作：提前发帖、换车（仅断裂后可用）。
-- 踩空 / 踩到油门的后果规则由实施计划第 4.1 节 B2 留空，这里只做"待确认"占位，不代决定。
local UI = require("urhox-libs/UI")
local BrakeTestDemo = require("ui.BrakeTestDemo")
local Session = require("core.Session")
local View = {}

---@class CockpitCallbacks
---@field onConfirm fun(source: string)
---@field onSelect fun(index: integer)
---@field onPost fun()
---@field onChangeVehicle fun()
---@field onBackToMenu fun()

---@class CockpitView
---@field root Widget
---@field testView BrakeTestDemoView
---@field RefreshHud fun(self: CockpitView, session: SessionModel, shoeName: string)
---@field ShowPending fun(self: CockpitView, outcome: string)
---@field HidePending fun(self: CockpitView)

---@param landingConfig LandingConfig
---@param demo BrakeTestDemoConfig
---@param flow SessionFlowConfig
---@param callbacks CockpitCallbacks
---@return CockpitView
function View.Create(landingConfig, demo, flow, callbacks)
    local weatherLabel = UI.Label { id = "cockpitWeather", text = "", fontSize = 13 }
    local vehicleLabel = UI.Label { id = "cockpitVehicle", text = "", fontSize = 13 }
    local chanceLabel = UI.Label { id = "cockpitChance", text = "", fontSize = 13 }
    local shoeLabel = UI.Label { id = "cockpitShoe", text = "", fontSize = 13 }
    -- 窗外占位：正式美术到位后换成分层窗外图，这里只用色块表达天气差异。
    local skyPanel = UI.Panel {
        id = "cockpitSky", width = "100%", height = 72, borderRadius = 8,
        backgroundColor = { 122, 178, 226, 255 }, pointerEvents = "none",
    }
    local postButton = UI.Button {
        id = "cockpitPost", text = "发帖", variant = "primary", height = 52, flexGrow = 1,
        onClick = function() callbacks.onPost() end,
    }
    local vehicleButton = UI.Button {
        id = "cockpitVehicleBtn", text = "换车", variant = "secondary", height = 52, flexGrow = 1,
        onClick = function() callbacks.onChangeVehicle() end,
    }
    local menuButton = UI.Button {
        id = "cockpitMenu", text = "返回主界面", variant = "secondary", height = 44,
        onClick = function() callbacks.onBackToMenu() end,
    }
    local pendingTitle = UI.Label { text = "", fontSize = 18 }
    local pendingBody = UI.Label {
        text = "", fontSize = 12, width = "100%", whiteSpace = "normal",
    }
    local pendingPanel = UI.Panel {
        id = "cockpitPending", width = "100%", padding = 16, gap = 8,
        backgroundColor = { 250, 236, 214, 255 }, borderRadius = 8, visible = false,
        children = {
            pendingTitle, pendingBody,
            UI.Label {
                text = "后果规则留空：是否消耗机会、是否跳过第二轮、如何演出由作者确认后再接入。",
                fontSize = 11, width = "100%", whiteSpace = "normal",
            },
        },
    }

    local testView = BrakeTestDemo.Create(landingConfig,
        { lever = demo.lever, contact = demo.contact,
            showDebugState = demo.showDebugState, embedded = true,
            -- 正式流程在角色准备阶段定鞋，测试中不显示换鞋行。
            allowShoeSwitch = false },
        callbacks.onConfirm, callbacks.onSelect)

    local hudRow = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 12,
        children = { weatherLabel, vehicleLabel, chanceLabel, shoeLabel },
    }
    local page = UI.Card {
        width = "100%", maxWidth = 880, padding = 16, gap = 12,
        children = {
            UI.Label { text = "驾驶舱（骨架版）", fontSize = 22 },
            skyPanel,
            hudRow,
            pendingPanel,
            testView.root,
            UI.Panel { width = "100%", flexDirection = "row", gap = 8,
                children = { postButton, vehicleButton } },
            menuButton,
        },
    }
    local root = UI.Panel {
        width = "100%", height = "100%", backgroundColor = UI.Theme.Color("background"),
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%", nativeMenuInset = true, padding = 16,
                children = {
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexBasis = 0,
                        children = {
                            UI.Panel { width = "100%", alignItems = "center", paddingVertical = 8,
                                children = { page } },
                        },
                    },
                },
            },
        },
    }
    local view = { root = root, testView = testView }

    ---@param session SessionModel
    ---@param shoeName string
    function view:RefreshHud(session, shoeName)
        local weather = session:Weather()
        weatherLabel:SetText("天气：" .. weather.name)
        skyPanel:SetStyle({ backgroundColor = weather.sky })
        vehicleLabel:SetText("车辆：第 " .. session:VehicleIndex() .. " 台")
        chanceLabel:SetText(string.format("机会：%d / %d",
            session:TestsUsed(), session.flow.maxTests))
        shoeLabel:SetText("鞋型：" .. shoeName)
        local state = session:PostingState()
        if state == Session.POST_REQUIRED then
            postButton:SetText("发帖（第 3 次后必须发帖）")
            postButton:SetDisabled(false)
        elseif state == Session.POST_OPTIONAL then
            postButton:SetText("提前发帖")
            postButton:SetDisabled(false)
        else
            postButton:SetText("发帖（至少测试 1 次）")
            postButton:SetDisabled(true)
        end
        -- 换车只在真的断裂后可用；换车不重置总次数与历史。
        vehicleButton:SetDisabled(not session:CanChangeVehicle())
    end

    ---@param outcome string
    function view:ShowPending(outcome)
        if outcome == "throttle" then
            pendingTitle:SetText("踩到油门：后果待确认")
        else
            pendingTitle:SetText("踩空：后果待确认")
        end
        pendingBody:SetText("本次结果：" .. outcome
            .. "。是否消耗机会、是否跳过第二轮尚未定案，因此会话停在这里，不自动扣次也不免费重试。")
        pendingPanel:SetVisible(true)
    end

    function view:HidePending()
        pendingPanel:SetVisible(false)
    end

    return view
end

return View
