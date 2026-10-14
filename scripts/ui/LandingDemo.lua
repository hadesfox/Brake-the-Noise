-- P1.2 开发几何界面：画面和算法使用同一组轴对齐矩形，避免图形与接触面积不符。
local UI = require("urhox-libs/UI")
local Landing = require("gameplay.Landing")
local View = {}

---@class LandingDemoView
---@field root Widget
---@field lastState string
---@field lastShoe number
---@field Refresh fun(self: LandingDemoView, model: LandingModel)
---@field ShowPaused fun(self: LandingDemoView, paused: boolean)

---@param config LandingConfig
---@param onConfirm fun(source: string)
---@param onSelect fun(index: integer)
---@return LandingDemoView
function View.Create(config, onConfirm, onSelect)
    local caption = UI.Label { id = "demoCaption", text = "鞋底移动中", fontSize = 18 }
    local reading = UI.Label {
        id = "demoReading", text = "停点  —", fontSize = 14,
        width = "100%", whiteSpace = "normal",
    }
    local actionText = UI.Label { text = "确认 · 按停", fontSize = 18 }
    local selectedLabel = UI.Label { text = "鞋型：宽底占位", fontSize = 13 }
    local note = UI.Label {
        text = "鞋型仅用于开发；按停后可换鞋对比同一落点。",
        width = "100%", fontSize = 11, whiteSpace = "normal",
    }
    local pedal = UI.Panel {
        id = "landingPedal", position = "absolute", borderRadius = 0,
        backgroundColor = { 66, 79, 90, 255 }, pointerEvents = "none",
    }
    local center = UI.Panel {
        id = "demoCursor", position = "absolute", width = 6, height = 6,
        borderRadius = 0, backgroundColor = { 230, 75, 70, 255 }, pointerEvents = "none",
    }
    ---@type Panel[]
    local shoePanels = {}
    ---@type Panel[]
    local contactPanels = {}
    local maxParts = 0
    for _, shoe in ipairs(config.shoes) do maxParts = math.max(maxParts, #shoe.parts) end
    local boardChildren = { pedal }
    for i = 1, maxParts do
        local shoePart = UI.Panel {
            position = "absolute", borderRadius = 0,
            backgroundColor = { 23, 167, 176, 145 }, pointerEvents = "none",
        }
        local contactPart = UI.Panel {
            position = "absolute", borderRadius = 0,
            backgroundColor = { 246, 185, 62, 255 }, pointerEvents = "none", visible = false,
        }
        shoePanels[i] = shoePart
        contactPanels[i] = contactPart
        boardChildren[#boardChildren + 1] = shoePart
        boardChildren[#boardChildren + 1] = contactPart
    end
    boardChildren[#boardChildren + 1] = center
    local board = UI.Panel {
        id = "landingBoard", width = 280, height = 280, borderRadius = 0,
        backgroundColor = { 229, 236, 235, 255 }, overflow = "hidden",
        pointerEvents = "none", children = boardChildren,
    }
    ---@type Button[]
    local shoeButtons = {}
    for i, shoe in ipairs(config.shoes) do
        local index = i
        shoeButtons[i] = UI.Button {
            id = "shoe" .. i, text = shoe.name, fontSize = 11,
            height = 48, disabled = true,
            onClick = function(_, event)
                if not event or event:IsPrimaryAction() then onSelect(index) end
            end,
        }
    end
    local action = UI.Panel {
        id = "demoAction", width = "100%", height = 64,
        justifyContent = "center", alignItems = "center",
        backgroundColor = UI.Theme.Color("primary"),
        onPointerDown = function(event)
            if event:IsPrimaryAction() and event.isPrimary then
                event:StopPropagation()
                onConfirm(event.pointerType)
            end
        end,
        children = { actionText },
    }
    local card = UI.Card {
        width = "100%", maxWidth = 880, padding = 20, gap = 12,
        children = {
            UI.Label { text = "舆论刹车", fontSize = 24 },
            UI.Label { text = "P1.2 / 落点与接触面（开发几何版）", fontSize = 12 },
            UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 20,
                children = {
                    board,
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1, minWidth = 220, gap = 12,
                        children = {
                            caption,
                            selectedLabel,
                            reading,
                            UI.Panel {
                                width = "100%", flexDirection = "row", flexWrap = "wrap",
                                gap = 6, children = shoeButtons,
                            },
                            action,
                            note,
                        },
                    },
                },
            },
            UI.Label {
                text = "深灰：踏板 / 蓝绿：鞋底 / 金色：按停后的交集 / 红点：作用点",
                width = "100%", fontSize = 11, whiteSpace = "normal",
            },
            UI.Label {
                text = "空格 / 回车或点击确认；按停后用 ← → 或点按钮换鞋。数据不代表正式力度。",
                width = "100%", fontSize = 11, whiteSpace = "normal",
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
    local view = { root = root, lastState = "", lastShoe = 0 }

    ---@param model LandingModel
    function view:Refresh(model)
        local layout = board:GetLayout()
        local size = math.min(layout.w, layout.h)
        local shoe = assert(config.shoes[model.shoeIndex], "鞋型索引无效")
        pedal:SetStyle({ left = config.pedal.x * size, top = config.pedal.y * size,
            width = config.pedal.w * size, height = config.pedal.h * size })
        center:SetStyle({ left = model.x * size - 3, top = model.y * size - 3 })
        local contact = Landing.Contact(config.pedal, shoe, model.x, model.y)
        for i = 1, maxParts do
            local part = shoe.parts[i]
            local shoePanel = assert(shoePanels[i])
            local contactPanel = assert(contactPanels[i])
            shoePanel:SetVisible(part ~= nil)
            if part then
                shoePanel:SetStyle({ left = (model.x + part.x) * size,
                    top = (model.y + part.y) * size, width = part.w * size, height = part.h * size })
            end
            local overlap = contact.intersections[i]
            contactPanel:SetVisible(not model.moving and overlap ~= nil)
            if overlap then
                contactPanel:SetStyle({ left = overlap.x * size, top = overlap.y * size,
                    width = overlap.w * size, height = overlap.h * size })
            end
        end
        local state = model.moving and "moving" or "locked"
        selectedLabel:SetText("鞋型：" .. shoe.name)
        caption:SetText(model.moving and "鞋底移动中" or "落点已锁定")
        actionText:SetText(model.moving and "确认 · 按停" or "确认 · 再次测量")
        for _, button in ipairs(shoeButtons) do button:SetDisabled(model.moving) end
        self.lastState = state
        self.lastShoe = model.shoeIndex
        if model.moving then
            if reading:GetText() ~= "停点  —" then reading:SetText("停点  —") end
        else
            local text = string.format("停点  (%.3f, %.3f)\n接触面积  %.4f\n鞋底接触占比  %.1f%%\n踏板覆盖占比  %.1f%%",
                model.x, model.y, contact.area, contact.shoeCoverage * 100, contact.pedalCoverage * 100)
            if reading:GetText() ~= text then reading:SetText(text) end
        end
    end

    ---@param paused boolean
    function view:ShowPaused(paused)
        caption:SetText(paused and "已暂停 · 回到前台后继续"
            or self.lastState == "moving" and "鞋底移动中" or "落点已锁定")
    end

    return view
end

return View
