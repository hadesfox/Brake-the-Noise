-- 测试后的独立选择界面（骨架版）：继续测试 / 发帖。
--
-- 已确认规则：第一次测试后可提前发帖；第三次结束后必须发帖（此时"继续测试"不可用）。
-- 换车是叙事动作，只有真的断裂后可用，且不重置总次数与历史。
-- 这里只呈现选择，不替玩家决定，也不伪造发帖内容或传播结果。
local UI = require("urhox-libs/UI")
local Session = require("core.Session")
local View = {}

---@class DecisionCallbacks
---@field onContinue fun()
---@field onPost fun()
---@field onChangeVehicle fun()
---@field onBackToMenu fun()

---@class DecisionView
---@field root Widget

---@param session SessionModel
---@param callbacks DecisionCallbacks
---@return DecisionView
function View.Create(session, callbacks)
    local state = session:PostingState()
    local required = state == Session.POST_REQUIRED
    local summary = UI.Label {
        id = "decisionSummary", text = "", fontSize = 13, width = "100%", whiteSpace = "normal",
    }
    local note = UI.Label {
        id = "decisionNote", text = "", fontSize = 11, width = "100%", whiteSpace = "normal",
        fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
    }
    local continueButton = UI.Button {
        id = "decisionContinue", text = "继续测试", variant = "primary", height = 56, width = "100%",
        onClick = function() callbacks.onContinue() end,
    }
    local postButton = UI.Button {
        id = "decisionPost", text = "发帖", variant = required and "primary" or "secondary",
        height = 56, width = "100%",
        onClick = function() callbacks.onPost() end,
    }
    local vehicleButton = UI.Button {
        id = "decisionVehicle", text = "换车（仅断裂后可用）", variant = "secondary",
        height = 48, width = "100%",
        onClick = function() callbacks.onChangeVehicle() end,
    }
    local backButton = UI.Button {
        id = "decisionBack", text = "返回主界面", variant = "secondary", height = 44, width = "100%",
        onClick = function() callbacks.onBackToMenu() end,
    }

    local function Refresh()
        local used = session:TestsUsed()
        local last = session:LastTest()
        local resultText = last and ("第 " .. tostring(last.testIndex or last.sequence) .. " 次已记录")
            or "尚未记录测试"
        summary:SetText(string.format("已用机会 %d / %d ｜ %s", used, session.flow.maxTests, resultText))
        if required then
            note:SetText("总测试次数已用满，按已确认规则必须进入发帖。")
            continueButton:SetDisabled(true)
            continueButton:SetText("继续测试（机会已用满）")
            postButton:SetText("发帖（必须）")
        else
            note:SetText("可以继续下一次测试，也可以提前发帖。")
            continueButton:SetDisabled(false)
            continueButton:SetText("继续测试")
            postButton:SetText("提前发帖")
        end
        -- 换车只在真的断裂后可用；当前没有损伤判定，因此实际不会亮起。
        vehicleButton:SetDisabled(not session:CanChangeVehicle())
    end

    local card = UI.Card {
        width = "100%", maxWidth = 520, padding = 24, gap = 12,
        children = {
            UI.Label { text = "本次测试结束", fontSize = 22 },
            summary,
            note,
            UI.Divider { spacing = 4 },
            continueButton,
            postButton,
            vehicleButton,
            backButton,
        },
    }
    local root = UI.Panel {
        width = "100%", height = "100%", backgroundColor = UI.Theme.Color("background"),
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%", nativeMenuInset = true, padding = 16,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexBasis = 0,
                        children = {
                            UI.Panel { width = "100%", alignItems = "center", paddingVertical = 8,
                                children = { card } },
                        },
                    },
                },
            },
        },
    }
    Refresh()
    return { root = root }
end

return View
