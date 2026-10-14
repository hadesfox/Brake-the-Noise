-- 主界面（骨架版）。入口已确认：开始测试 / 测试档案。
-- 正式美术未到位，这里只用 UI 组件搭结构与文字；标题文字由程序绘制，不烘焙进图片。
local UI = require("urhox-libs/UI")
local View = {}

-- 主题色返回 table，LSP 需要显式收窄成 RGBAColor 才能通过 Label/Panel 属性检查。
local TEXT_SECONDARY = UI.Theme.Color("textSecondary") --[[@as RGBAColor]]

---@class MainMenuState
---@field hasArchive boolean

---@class MainMenuView
---@field root Widget

-- 测试档案属于 D4/D7 范围，当前没有存档层，这里明确说明未实现，不伪造历史记录。
---@param onStart fun()
---@param onArchive fun()
---@return MainMenuView
function View.Create(onStart, onArchive)
    local card = UI.Card {
        width = "100%", maxWidth = 520, padding = 28, gap = 14,
        children = {
            UI.Label { text = "舆论刹车", fontSize = 32, textAlign = "center", width = "100%" },
            UI.Label {
                text = "Brake the Noise · 骨架版（占位界面）",
                fontSize = 12, textAlign = "center", width = "100%",
                fontColor = TEXT_SECONDARY,
            },
            UI.Divider { spacing = 6 },
            UI.Button {
                id = "menuStart", text = "开始测试", variant = "primary",
                height = 56, width = "100%",
                onClick = function() onStart() end,
            },
            UI.Button {
                id = "menuArchive", text = "测试档案", variant = "secondary",
                height = 56, width = "100%",
                onClick = function() onArchive() end,
            },
            UI.Label {
                id = "menuNote",
                text = "测试档案需要存档层（D4/D7），当前未实现，点开只显示说明。",
                fontSize = 11, width = "100%", whiteSpace = "normal",
                fontColor = TEXT_SECONDARY,
            },
        },
    }
    local root = UI.Panel {
        width = "100%", height = "100%", backgroundColor = UI.Theme.Color("background"),
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%", nativeMenuInset = true, padding = 16,
                justifyContent = "center", alignItems = "center",
                children = { card },
            },
        },
    }
    return { root = root }
end

return View
