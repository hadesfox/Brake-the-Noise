-- 角色准备（骨架版）。开局确定衣服、裤子、鞋子。
--
-- 已确认：鞋子影响接触面积，其余服饰不擅自增加数值影响。
-- 当前鞋子是开发占位鞋型；衣服与裤子只是外观占位，没有换装美术，也没有数值作用。
local UI = require("urhox-libs/UI")
local View = {}

---@class PrepSelection
---@field shoeIndex integer
---@field clothingIndex integer
---@field trousersIndex integer

---@class CharacterPrepView
---@field root Widget
---@field GetSelection fun(self: CharacterPrepView): PrepSelection

---@param flow SessionFlowConfig
---@param shoes LandingShoe[]
---@param onConfirm fun(selection: PrepSelection)
---@param onBack fun()
---@return CharacterPrepView
function View.Create(flow, shoes, onConfirm, onBack)
    local selection = { shoeIndex = 1, clothingIndex = 1, trousersIndex = 1 }
    local shoeLabel = UI.Label { text = "", fontSize = 13, width = "100%", whiteSpace = "normal" }
    local clothingLabel = UI.Label { text = "", fontSize = 13, width = "100%", whiteSpace = "normal" }
    local trousersLabel = UI.Label { text = "", fontSize = 13, width = "100%", whiteSpace = "normal" }
    ---@type Button[]
    local shoeButtons = {}
    ---@type Button[]
    local clothingButtons = {}
    ---@type Button[]
    local trouserButtons = {}

    local function Refresh()
        local shoe = assert(shoes[selection.shoeIndex], "鞋型索引无效")
        shoeLabel:SetText("鞋子：" .. shoe.name .. "（决定接触面积）")
        local clothing = flow.character.clothing[selection.clothingIndex]
        clothingLabel:SetText("上衣：" .. (clothing and clothing.name or "无"))
        local trousers = flow.character.trousers[selection.trousersIndex]
        trousersLabel:SetText("裤子：" .. (trousers and trousers.name or "无"))
        for i, button in ipairs(shoeButtons) do button:SetDisabled(i == selection.shoeIndex) end
        for i, button in ipairs(clothingButtons) do button:SetDisabled(i == selection.clothingIndex) end
        for i, button in ipairs(trouserButtons) do button:SetDisabled(i == selection.trousersIndex) end
    end

    for i, shoe in ipairs(shoes) do
        shoeButtons[i] = UI.Button {
            id = "prepShoe" .. i, text = shoe.name, fontSize = 12, height = 48,
            onClick = function() selection.shoeIndex = i; Refresh() end,
        }
    end
    for i, clothing in ipairs(flow.character.clothing) do
        clothingButtons[i] = UI.Button {
            id = "prepCloth" .. i, text = clothing.name, fontSize = 12, height = 44,
            onClick = function() selection.clothingIndex = i; Refresh() end,
        }
    end
    for i, trousers in ipairs(flow.character.trousers) do
        trouserButtons[i] = UI.Button {
            id = "prepTrouser" .. i, text = trousers.name, fontSize = 12, height = 44,
            onClick = function() selection.trousersIndex = i; Refresh() end,
        }
    end

    local card = UI.Card {
        width = "100%", maxWidth = 720, padding = 20, gap = 12,
        children = {
            UI.Label { text = "角色准备", fontSize = 22 },
            UI.Label {
                text = "鞋子影响接触面积；衣服与裤子当前只有外观占位，不产生数值影响。",
                fontSize = 11, width = "100%", whiteSpace = "normal",
                fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
            },
            UI.Divider { spacing = 4 },
            UI.Label { text = "鞋子", fontSize = 14 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6,
                children = shoeButtons },
            shoeLabel,
            UI.Label { text = "上衣（外观占位）", fontSize = 14, marginTop = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6,
                children = clothingButtons },
            clothingLabel,
            UI.Label { text = "裤子（外观占位）", fontSize = 14, marginTop = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6,
                children = trouserButtons },
            trousersLabel,
            UI.Divider { spacing = 4 },
            UI.Button {
                id = "prepConfirm", text = "确认并上车", variant = "primary",
                height = 56, width = "100%",
                onClick = function() onConfirm(selection) end,
            },
            UI.Button {
                id = "prepBack", text = "返回主界面", variant = "secondary",
                height = 44, width = "100%",
                onClick = function() onBack() end,
            },
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
                                children = { card } },
                        },
                    },
                },
            },
        },
    }
    Refresh()
    local view = { root = root }
    ---@return PrepSelection
    function view:GetSelection() return selection end
    return view
end

return View
