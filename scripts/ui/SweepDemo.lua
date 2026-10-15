-- 手感台仅用于开发验证，归一化读数不进入正式游戏 HUD 或测试档案。
local UI = require("urhox-libs/UI")

local View = {}

---@param onConfirm fun(source: string)
---@return table
function View.Create(onConfirm)
    local caption = UI.Label { id = "demoCaption", text = "游标移动中", fontSize = 20, fontWeight = "bold" }
    local reading = UI.Label { id = "demoReading", text = "停点  —", fontSize = 18 }
    local note = UI.Label {
        text = "这里只记录停点，不代表真实踩踏力度。",
        fontSize = 12, whiteSpace = "normal", width = "100%",
    }
    local actionText = UI.Label {
        text = "确认 · 按停", fontSize = 18, fontWeight = "bold",
        textAlign = "center",
    }
    local cursor = UI.Panel {
        id = "demoCursor", position = "absolute", left = 0, top = 0, bottom = 0, width = 12,
        borderRadius = 0,
        backgroundColor = UI.Theme.Color("primary"), pointerEvents = "none",
    }
    local track = UI.Panel {
        width = "100%", height = 56, borderRadius = 0,
        backgroundColor = UI.Theme.Color("border"),
        overflow = "hidden", pointerEvents = "none",
        children = {
            UI.Panel {
                position = "absolute", left = "50%", top = 12, bottom = 12, width = 2,
                backgroundColor = UI.Theme.Color("surface"), pointerEvents = "none",
            },
            cursor,
        },
    }
    -- 用按下而不是抬起采样：长按不会增加一次判定，也不会产生延迟停点。
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
        width = "100%", maxWidth = 880, padding = 24, gap = 16,
        children = {
            UI.Label { text = "舆论刹车", fontSize = 28, fontWeight = "bold" },
            UI.Label { text = "第一步 / 归一化手感台（开发版）", fontSize = 13 },
            UI.Divider {},
            caption,
            track,
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between",
                children = { UI.Label { text = "左端" }, UI.Label { text = "右端" } },
            },
            reading,
            action,
            UI.Label {
                text = "PC：空格 / 回车，或点击确认区；手机：点确认区。",
                fontSize = 12, width = "100%", whiteSpace = "normal",
            },
            note,
        },
    }
    local root = UI.Panel {
        width = "100%", height = "100%", backgroundColor = UI.Theme.Color("background"),
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%", nativeMenuInset = true,
                padding = 16,
                children = {
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexBasis = 0, scrollY = true,
                        children = {
                            UI.Panel {
                                width = "100%", alignItems = "center", paddingVertical = 8,
                                children = { card },
                            },
                        },
                    },
                },
            },
        },
    }
    local view = { root = root }

    ---@param position number
    function view:SetPosition(position)
        local layout = track:GetLayout()
        local travel = math.max(0, layout.w - 12)
        cursor:SetStyle({ left = position * travel })
    end

    ---@param position number
    ---@param attempt integer
    ---@param source string
    function view:ShowLocked(position, attempt, source)
        caption:SetText("已按停 · 第 " .. attempt .. " 次测量")
        reading:SetText(string.format("停点  %.3f", position))
        actionText:SetText("确认 · 再次测量")
        note:SetText("输入来源：" .. source .. "。可重复测量，仅用于开发手感验证。")
    end

    function view:ShowMoving()
        caption:SetText("游标移动中")
        reading:SetText("停点  —")
        actionText:SetText("确认 · 按停")
        note:SetText("这里只记录停点，不代表真实踩踏力度。")
    end

    ---@param paused boolean
    function view:ShowPaused(paused)
        if paused then
            caption:SetText("已暂停 · 回到前台后继续")
        else
            caption:SetText(actionText:GetText() == "确认 · 按停" and "游标移动中" or "已按停")
        end
    end

    return view
end

return View
