-- 开车前准备（骨架版）。第一人称驾驶舱内，第一人称体验。
--
-- 已确认：空调与座椅是可见可操作的实体控件；隐藏交互不加解释箭头，也不显示隐藏数值。
-- 这里用普通控件占位，正式版本按美术指南批次 B/C 替换为驾驶舱分层资产与热点。
--
-- 两段：
--   prep       —— 开关空调、调整座椅，确认后点火；
--   accelerate —— 从 0 加速到时速 100 km/h，到达后进入刹车时刻。
-- 加速时长来自 config/Flow.lua，是骨架占位值，不是最终节奏。
local UI = require("urhox-libs/UI")
local Acceleration = require("core.Acceleration")
local View = {}

---@class PreDriveSelection
---@field acOn boolean
---@field seat number 0～1 的座椅位置占位

---@class PreDriveView
---@field root Widget
---@field Update fun(self: PreDriveView, dt: number)
---@field IsAccelerating fun(self: PreDriveView): boolean
---@field GetSelection fun(self: PreDriveView): PreDriveSelection

---@param flow SessionFlowConfig
---@param weather SessionWeather
---@param shoeName string
---@param onBrakeTime fun(selection: PreDriveSelection)
---@return PreDriveView
function View.Create(flow, weather, shoeName, onBrakeTime)
    local acceleration = Acceleration.Create(flow.acceleration)
    ---@type PreDriveSelection
    local selection = { acOn = flow.preDrive.ac.on, seat = flow.preDrive.seat.position }

    -- 前向声明：控件回调互相引用。
    ---@type fun()
    local RefreshPrep

    local acLabel = UI.Label { id = "preDriveAc", text = "", fontSize = 13 }
    local seatLabel = UI.Label { id = "preDriveSeat", text = "", fontSize = 13 }
    local speedLabel = UI.Label { id = "preDriveSpeed", text = "时速 0 km/h", fontSize = 28 }
    local hintLabel = UI.Label {
        id = "preDriveHint", text = "", fontSize = 11, width = "100%",
        whiteSpace = "normal", fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
    }
    local skyPanel = UI.Panel {
        id = "preDriveSky", width = "100%", height = 96, borderRadius = 8,
        backgroundColor = weather.sky, pointerEvents = "none",
    }
    local acButton = UI.Button {
        id = "preDriveAcBtn", text = "", variant = "secondary", height = 52, flexGrow = 1,
        onClick = function()
            selection.acOn = not selection.acOn
            RefreshPrep()
        end,
    }
    -- 座椅只有一轴占位；不加解释箭头，也不显示百分比。
    local seatSlider = UI.Slider {
        id = "preDriveSeatSlider", value = selection.seat * 100, min = 0, max = 100, step = 1,
        onChange = function(_, value)
            selection.seat = value / 100
            RefreshPrep()
        end,
    }
    local startButton = UI.Button {
        id = "preDriveStart", text = "点火 · 加速到 100", variant = "primary",
        height = 56, width = "100%",
        onClick = function()
            if acceleration.running then return end
            acceleration:Reset()
            acceleration:Start()
            RefreshPrep()
        end,
    }
    local prepPanel = UI.Panel {
        id = "preDrivePrep", width = "100%", gap = 10,
        children = {
            UI.Label {
                text = "开车前准备：空调与座椅可操作；隐藏交互不加提示。",
                fontSize = 11, width = "100%", whiteSpace = "normal",
                fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
            },
            acLabel,
            acButton,
            seatLabel,
            seatSlider,
            startButton,
        },
    }
    local accelPanel = UI.Panel {
        id = "preDriveAccel", width = "100%", gap = 10, visible = false,
        children = {
            speedLabel,
            UI.Label {
                text = "加速阶段占位时长见 config/Flow.lua；正式节奏约 15 秒，不是最终值。",
                fontSize = 11, width = "100%", whiteSpace = "normal",
                fontColor = UI.Theme.Color("textSecondary") --[[@as RGBAColor]],
            },
        },
    }
    local card = UI.Card {
        width = "100%", maxWidth = 640, padding = 20, gap = 12,
        children = {
            UI.Label { text = "驾驶舱 · 发车前", fontSize = 22 },
            skyPanel,
            UI.Label {
                id = "preDriveMeta",
                text = "天气：" .. weather.name .. " ｜ 鞋型：" .. shoeName,
                fontSize = 13,
            },
            hintLabel,
            prepPanel,
            accelPanel,
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
    local view = { root = root }

    function RefreshPrep()
        acLabel:SetText("空调：" .. (selection.acOn and "开" or "关"))
        acButton:SetText(selection.acOn and "关掉空调" or "打开空调")
        seatLabel:SetText("座椅位置（占位单轴）")
        speedLabel:SetText(string.format("时速 %d km/h", math.floor(acceleration.speed + 0.5)))
        if acceleration.running then
            prepPanel:SetVisible(false)
            accelPanel:SetVisible(true)
            hintLabel:SetText("加速中…")
        else
            prepPanel:SetVisible(true)
            accelPanel:SetVisible(false)
            hintLabel:SetText("调整完成后点火；空调与座椅只做记录，不显示隐藏数值。")
        end
    end

    ---@param dt number
    function view:Update(dt)
        if not acceleration.running then return end
        local before = acceleration.completed
        acceleration:Update(dt)
        speedLabel:SetText(string.format("时速 %d km/h", math.floor(acceleration.speed + 0.5)))
        if acceleration.completed and not before then
            onBrakeTime(selection)
        end
    end

    ---@return boolean
    function view:IsAccelerating()
        return acceleration.running
    end

    ---@return PreDriveSelection
    function view:GetSelection()
        return { acOn = selection.acOn, seat = selection.seat }
    end

    RefreshPrep()
    return view
end
return View
