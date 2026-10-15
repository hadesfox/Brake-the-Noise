-- 测试档案（骨架版）。设计上它同时承担成就收集与完整因素展示，
-- 但存档层与正式因素字段属 D4/D7，当前没有持久化，也没有可展示的真实历史。
-- 因此这里明确显示"未实现"，不伪造任何测试记录。
local UI = require("urhox-libs/UI")
local View = {}

---@class ArchiveView
---@field root Widget

---@param onBack fun()
---@return ArchiveView
function View.Create(onBack)
    local card = UI.Card {
        width = "100%", maxWidth = 640, padding = 24, gap = 12,
        children = {
            UI.Label { text = "测试档案", fontSize = 22 },
            UI.Label {
                text = "当前未实现：没有存档层，也没有正式因素字段（力度、落点、疲劳、温度、暴躁等）。",
                fontSize = 12, width = "100%", whiteSpace = "normal",
            },
            UI.Label {
                text = "档案需要先完成 D4 的会话记录与 D7 的持久化核验；在此之前不显示任何伪造历史。",
                fontSize = 12, width = "100%", whiteSpace = "normal",
                fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
            },
            UI.Divider { spacing = 4 },
            UI.Label {
                text = "计划中的字段（未实现）：\n· 每次测试的力度、落点、结果\n· 疲劳、温度、暴躁等隐藏因素\n· 换车历史与原帖副本\n· 结局与因果链",
                fontSize = 12, width = "100%", whiteSpace = "normal",
            },
            UI.Button {
                id = "archiveBack", text = "返回主界面", variant = "primary",
                height = 52, width = "100%",
                onClick = function() onBack() end,
            },
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
    return { root = root }
end

return View
