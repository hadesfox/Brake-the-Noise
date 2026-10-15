-- 上车过场（骨架版）。正式美术是 2D 卡通过场，当前用占位文字与色块表达节奏。
--
-- 过场只是叙事动作，不做预算管理，也不改变任何已确认结果。
-- 时长与内容属演出，正式版本按美术指南批次 D 制作；这里不伪造动画时长。
local UI = require("urhox-libs/UI")
local View = {}

-- 实例类型名与模块名分开：BoardingView 是实例，View 是模块表。
---@class BoardingView
---@field root Widget
---@field Advance fun(self: BoardingView): boolean 推进到下一段；返回 false 表示已结束

---@param weather SessionWeather
---@param shoeName string
---@return BoardingView
function View.Create(weather, shoeName)
    local title = UI.Label { id = "boardingTitle", text = "上车", fontSize = 26 }
    local line = UI.Label {
        id = "boardingLine", text = "", fontSize = 14, width = "100%",
        whiteSpace = "normal", textAlign = "center",
    }
    local hint = UI.Label {
        text = "点击或按空格继续", fontSize = 11, width = "100%",
        textAlign = "center", fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
    }
    -- 三段占位节奏：系好安全带 → 关车门 → 面向踏板。正式版本替换为过场图/动画。
    ---@type { title: string, text: string }[]
    local beats = {
        { title = "上车", text = "窗外天气：" .. weather.name .. "。系好安全带。" },
        { title = "坐定", text = "鞋型：" .. shoeName .. "。双手离开方向盘，准备面对踏板。" },
        { title = "准备", text = "调整座椅与空调，然后点火。" },
    }
    -- index 表示"已推进的段数"：0 显示第 1 段，1 显示第 2 段，依此类推。
    local index = 0
    -- 点击推进由 stage 触发；built 在后面构建，所以用可空引用延迟绑定。
    ---@type BoardingView?
    local builtRef
    local skyPanel = UI.Panel {
        id = "boardingSky", width = "100%", height = 120, borderRadius = 8,
        backgroundColor = weather.sky, pointerEvents = "none",
    }
    local stage = UI.Panel {
        id = "boardingStage", width = "100%", height = 64, justifyContent = "center",
        alignItems = "center", backgroundColor = UI.Theme.Color("surface"), borderRadius = 8,
        onPointerDown = function(event)
            if event:IsPrimaryAction() and event.isPrimary then
                event:StopPropagation()
                if builtRef then builtRef:Advance() end
            end
        end,
        children = { hint },
    }
    local card = UI.Card {
        width = "100%", maxWidth = 560, padding = 24, gap = 14,
        children = {
            title, skyPanel, line, stage,
            UI.Label {
                text = "过场为占位内容；正式 2D 过场按美术指南批次 D 制作。",
                fontSize = 11, width = "100%", whiteSpace = "normal",
                fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
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
    local function Show()
        -- index 是已推进段数，因此当前显示第 index + 1 段。
        local position = math.max(1, math.min(#beats, index + 1))
        local beat = assert(beats[position], "过场段索引越界")
        title:SetText(beat.title)
        line:SetText(beat.text)
    end

    -- 返回 false 表示三段已走完，调用方负责切场景。
    ---@return boolean
    local function Advance()
        if index + 1 >= #beats then return false end
        index = index + 1
        Show()
        return true
    end

    ---@type BoardingView
    local built = { root = root, Advance = Advance }
    builtRef = built
    Show()
    return built
end

return View
