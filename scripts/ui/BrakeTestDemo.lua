-- P1.3f 开发界面：第一轮落点/接触面 → 第二轮力度心理曲线，共用同一个确认操作。
-- 画面里的踏板、鞋底、交集矩形与算法使用同一组数据，避免图形与读数不符。
--
-- 隐藏状态可见范围：正式局内不得出现暴躁、疲劳、甜蜜区中心这类数字。
-- 它们只在 showDebugState 打开的开发面板里出现，方便本地核对模型，不作为正式 HUD。
local UI = require("urhox-libs/UI")
local Landing = require("gameplay.Landing")
local ForceCurve = require("gameplay.ForceCurve")
local Lever = require("gameplay.Lever")
local ContactMapping = require("gameplay.ContactMapping")
local ForceCurveStrip = require("ui.ForceCurveStrip")
local View = {}

---@class BrakeTestDemoConfig
---@field lever LeverConfig
---@field contact ContactMappingConfig
---@field showDebugState boolean 是否显示隐藏状态数字；正式局必须为 false

---@class BrakeTestDemoView
---@field root Widget
---@field lastState string
---@field Refresh fun(self: BrakeTestDemoView, landing: LandingModel, force: ForceCurveModel, phase: string)
---@field ShowPaused fun(self: BrakeTestDemoView, paused: boolean)

-- 阶段常量与 main.lua 共用同一份字符串，避免两处字面量漂移。
View.PHASE_LANDING = "landing"
View.PHASE_FORCE = "force"
View.PHASE_DONE = "done"

---@param config LandingConfig
---@param demo BrakeTestDemoConfig
---@param onConfirm fun(source: string)
---@param onSelect fun(index: integer)
---@return BrakeTestDemoView
function View.Create(config, demo, onConfirm, onSelect)
    local phaseLabel = UI.Label { id = "phaseLabel", text = "第 1 轮 · 落点与接触面", fontSize = 12 }
    local caption = UI.Label { id = "demoCaption", text = "鞋底移动中", fontSize = 18 }
    local reading = UI.Label {
        id = "demoReading", text = "停点  —", fontSize = 14,
        width = "100%", whiteSpace = "normal",
    }
    -- 隐藏状态只在开发面板出现；正式局通过 showDebugState=false 关闭。
    local debugReading = UI.Label {
        id = "demoDebug", text = "", fontSize = 11,
        width = "100%", whiteSpace = "normal", visible = demo.showDebugState,
    }
    local selectedLabel = UI.Label { text = "鞋型：宽底占位", fontSize = 13 }
    local actionText = UI.Label { text = "确认 · 按停", fontSize = 18 }
    local note = UI.Label {
        text = "鞋型仅用于开发；第 1 轮按停后可换鞋对比同一落点。",
        width = "100%", fontSize = 11, whiteSpace = "normal",
    }
    local pedal = UI.Panel {
        id = "landingPedal", position = "absolute", borderRadius = 0,
        backgroundColor = { 66, 79, 90, 255 }, pointerEvents = "none",
    }
    -- 油门：刹车踏板旁边的窄长踏板；与刹车用同一次真实交集判定。
    local throttle = UI.Panel {
        id = "landingThrottle", position = "absolute", borderRadius = 0,
        backgroundColor = { 205, 133, 63, 255 }, pointerEvents = "none",
        visible = config.throttle ~= nil,
    }
    -- 踩到油门时的交集高亮，与刹车交集用不同颜色区分。
    local throttleHit = UI.Panel {
        id = "landingThrottleHit", position = "absolute", borderRadius = 0,
        backgroundColor = { 231, 76, 60, 255 }, pointerEvents = "none", visible = false,
    }
    -- 开发用进度读数：实时显示本次扫过的落点里有多少是踩空、其中多少踩到油门。
    -- 正式局不显示；这里只为让作者看到真实概率，避免用"面积很小"估算稀有度。
    local throttleStats = { samples = 0, missed = 0, throttle = 0 }
    local center = UI.Panel {
        id = "demoCursor", position = "absolute", width = 6, height = 6,
        borderRadius = 0, backgroundColor = { 230, 75, 70, 255 }, pointerEvents = "none",
    }
    -- 受力重心：真实交集面积重心，和鞋中心红点分开显示。
    local centroid = UI.Panel {
        id = "demoCentroid", position = "absolute", width = 6, height = 6,
        borderRadius = 0, backgroundColor = { 142, 68, 173, 255 },
        pointerEvents = "none", visible = false,
    }
    -- 杆与支点：与 L 使用同一份归一化几何。
    local leverArm = UI.Panel {
        id = "demoLever", position = "absolute", borderRadius = 0,
        backgroundColor = { 120, 132, 140, 220 }, pointerEvents = "none",
    }
    local pivot = UI.Panel {
        id = "demoPivot", position = "absolute", width = 8, height = 8,
        borderRadius = 0, backgroundColor = { 52, 73, 94, 255 }, pointerEvents = "none",
    }
    ---@type Panel[]
    local shoePanels = {}
    ---@type Panel[]
    local contactPanels = {}
    local maxParts = 0
    for _, shoe in ipairs(config.shoes) do maxParts = math.max(maxParts, #shoe.parts) end
    local boardChildren = { pedal, throttle, leverArm, pivot }
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
    boardChildren[#boardChildren + 1] = throttleHit
    boardChildren[#boardChildren + 1] = center
    boardChildren[#boardChildren + 1] = centroid
    local board = UI.Panel {
        id = "landingBoard", width = 280, height = 280, borderRadius = 0,
        backgroundColor = { 229, 236, 235, 255 }, overflow = "hidden",
        pointerEvents = "none", children = boardChildren,
    }
    local landingBox = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 20,
        children = {
            board,
            UI.Panel {
                flexGrow = 1, flexShrink = 1, minWidth = 220, gap = 12,
                children = { caption, selectedLabel, reading, debugReading },
            },
        },
    }
    local strip = ForceCurveStrip { id = "forceStrip" }
    local forceBox = UI.Panel {
        width = "100%", flexDirection = "column", gap = 10,
        children = {
            strip,
            UI.Label {
                text = "曲线两端大、中间小；甜蜜区是最好控力的低力度段，命中不保证断裂。",
                width = "100%", fontSize = 11, whiteSpace = "normal",
            },
            reading,
            debugReading,
        },
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
    local shoeRow = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        gap = 6, children = shoeButtons,
    }
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
            UI.Label { text = "P1.3f / 新设计对齐（开发版）", fontSize = 12 },
            phaseLabel,
            landingBox,
            forceBox,
            shoeRow,
            action,
            note,
            UI.Label {
                text = "深灰：刹车踏板 / 棕色：油门 / 蓝绿：鞋底 / 金色：刹车交集 / 红色：油门交集",
                width = "100%", fontSize = 11, whiteSpace = "normal",
            },
            UI.Label {
                text = "红点：鞋中心 / 紫点：受力重心 / 深蓝点：支点",
                width = "100%", fontSize = 11, whiteSpace = "normal",
            },
            UI.Label {
                text = "空格 / 回车或点击确认按停；第 1 轮锁定后用 ← → 或按钮换鞋。数据不代表正式力度。",
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
    local view = { root = root, lastState = "" }

    ---@param landing LandingModel
    ---@param force ForceCurveModel
    ---@param phase string
    function view:Refresh(landing, force, phase)
        local landingActive = phase == View.PHASE_LANDING
        landingBox:SetVisible(landingActive)
        forceBox:SetVisible(not landingActive)
        shoeRow:SetVisible(landingActive)
        note:SetVisible(landingActive)
        -- 离开第一轮就禁用按钮，否则结束态会留着可点却无效的换鞋按钮。
        for _, button in ipairs(shoeButtons) do
            button:SetDisabled(not landingActive or landing.moving)
        end
        strip:SetModel(force)
        if phase == View.PHASE_LANDING then
            local layout = board:GetLayout()
            local size = math.min(layout.w, layout.h)
            local shoe = assert(config.shoes[landing.shoeIndex], "鞋型索引无效")
            local pivotLeft = demo.lever.pivotX * size
            local pivotTop = demo.lever.pivotY * size
            pivot:SetStyle({ left = pivotLeft - 4, top = pivotTop - 4 })
            pedal:SetStyle({ left = config.pedal.x * size, top = config.pedal.y * size,
                width = config.pedal.w * size, height = config.pedal.h * size })
            if config.throttle then
                throttle:SetStyle({ left = config.throttle.x * size, top = config.throttle.y * size,
                    width = config.throttle.w * size, height = config.throttle.h * size })
            end
            center:SetStyle({ left = landing.x * size - 3, top = landing.y * size - 3 })
            local contact = Landing.Contact(config.pedal, shoe, landing.x, landing.y, config.throttle)
            -- 开发统计：累计本次扫过的落点，得出踩空里踩到油门的真实比例。
            if demo.showDebugState and landing.moving then
                throttleStats.samples = throttleStats.samples + 1
                if contact.outcome == "missed" then
                    throttleStats.missed = throttleStats.missed + 1
                elseif contact.outcome == "throttle" then
                    throttleStats.throttle = throttleStats.throttle + 1
                end
            end
            -- 只在结果是踩到油门时高亮；鞋底横跨两者而正常刹车时结果仍是 brake。
            local throttleVisible = not landing.moving and contact.outcome == "throttle"
            throttleHit:SetVisible(throttleVisible)
            if throttleVisible and config.throttle then
                local throttleRects = Landing.OverlapRects(config.throttle, shoe, landing.x, landing.y)
                local firstThrottle = throttleRects[1]
                if firstThrottle then
                    throttleHit:SetStyle({ left = firstThrottle.x * size, top = firstThrottle.y * size,
                        width = firstThrottle.w * size, height = firstThrottle.h * size })
                end
            end
            -- 杆从支点连到受力重心；锁点前受力重心未知，杆先连到鞋中心。
            local armTargetX = contact.centroidX or landing.x
            local armTargetY = contact.centroidY or landing.y
            local armX, armY = armTargetX * size, armTargetY * size
            local deltaX, deltaY = armX - pivotLeft, armY - pivotTop
            local armLength = math.sqrt(deltaX * deltaX + deltaY * deltaY)
            leverArm:SetVisible(armLength > 0.001)
            if armLength > 0.001 then
                -- 杆的本地"向下"是 +Y；绕中心转到支点→受力重心方向。
                leverArm:SetStyle({ left = (pivotLeft + armX) / 2 - 1,
                    top = (pivotTop + armY) / 2 - armLength / 2, width = 2, height = armLength,
                    rotate = math.deg(math.atan(-deltaX, deltaY)) })
            end
            centroid:SetVisible(contact.hasContact and not landing.moving)
            if contact.hasContact and contact.centroidX and contact.centroidY then
                centroid:SetStyle({ left = contact.centroidX * size - 3,
                    top = contact.centroidY * size - 3 })
            end
            for i = 1, maxParts do
                local part = shoe.parts[i]
                local shoePanel = assert(shoePanels[i])
                local contactPanel = assert(contactPanels[i])
                shoePanel:SetVisible(part ~= nil)
                if part then
                    shoePanel:SetStyle({ left = (landing.x + part.x) * size,
                        top = (landing.y + part.y) * size, width = part.w * size, height = part.h * size })
                end
                local overlap = contact.intersections[i]
                contactPanel:SetVisible(not landing.moving and overlap ~= nil)
                if overlap then
                    contactPanel:SetStyle({ left = overlap.x * size, top = overlap.y * size,
                        width = overlap.w * size, height = overlap.h * size })
                end
            end
            phaseLabel:SetText("第 1 轮 · 落点与接触面")
            caption:SetText(landing.moving and "鞋底移动中" or "落点已锁定")
            selectedLabel:SetText("鞋型：" .. shoe.name)
            actionText:SetText(landing.moving and "确认 · 按停" or "确认 · 进入第 2 轮")
            self.lastState = landing.moving and "moving" or "locked"
            if landing.moving then
                if reading:GetText() ~= "停点  —" then reading:SetText("停点  —") end
            else
                local mapping = ContactMapping.Evaluate(demo.contact,
                    contact.pedalCoverage, contact.shoeCoverage)
                local text
                if contact.outcome == "throttle" then
                    text = string.format(
                        "鞋中心  (%.3f, %.3f)\n踩到油门：本次不进入刹车载荷计算\n油门交集面积  %.4f",
                        landing.x, landing.y, contact.throttleArea)
                elseif contact.hasContact and contact.centroidX and contact.centroidY then
                    local arm = Lever.Arm(demo.lever, contact.centroidX, contact.centroidY)
                    text = string.format(
                        "鞋中心  (%.3f, %.3f)\n受力重心  (%.3f, %.3f)\n力臂 L  %.4f\n接触面积  %.4f\n踏板覆盖  %.1f%% ｜ 鞋底接触  %.1f%%\nA集中  %.3f × E传导  %.3f = A有效  %.3f",
                        landing.x, landing.y, contact.centroidX, contact.centroidY, arm.l,
                        contact.area, contact.pedalCoverage * 100, contact.shoeCoverage * 100,
                        mapping.concentrate, mapping.conduction, mapping.effective)
                else
                    text = string.format(
                        "鞋中心  (%.3f, %.3f)\n踩空：没有受力重心，不进入载荷计算",
                        landing.x, landing.y)
                end
                if reading:GetText() ~= text then reading:SetText(text) end
            end
            if demo.showDebugState then
                -- 分母用"踩空"而不是全部落点，因为油门只可能发生在踩空时。
                local stats = "开发：显示受力重心、L 与 A有效；正式局内不得出现隐藏状态数字。"
                if throttleStats.missed > 0 then
                    stats = stats .. string.format("\n开发统计：本次扫过 %d 点，踩空 %d 点，其中踩到油门 %d 点（%.2f%%）",
                        throttleStats.samples, throttleStats.missed, throttleStats.throttle,
                        throttleStats.throttle / throttleStats.missed * 100)
                end
                debugReading:SetText(stats)
            else
                debugReading:SetText("")
            end
        else
            phaseLabel:SetText(phase == View.PHASE_DONE and "本轮两轮判定已结束"
                or "第 2 轮 · 力度")
            caption:SetText(force.moving and "力度游标移动中" or "力度已锁定")
            actionText:SetText(force.moving and "确认 · 按停" or "确认 · 开始下一次测量")
            self.lastState = force.moving and "moving" or "locked"
            local sweetHalf = ForceCurve.SweetHalf(force.spec, force.agitation)
            local text = string.format(
                "踩踏力度 F  %.1f N\n意图力度  %.1f N\n甜蜜区宽度  %.1f%%（半宽 %.3f）",
                force.force, force.intentForce, sweetHalf * 200, sweetHalf)
            if reading:GetText() ~= text then reading:SetText(text) end
            -- 隐藏状态只进开发面板，且仅当开关打开。
            if demo.showDebugState then
                local debugText = string.format(
                    "开发：暴躁 %.2f ｜ 疲劳 %.2f ｜ 甜蜜区中心 %.3f ｜ 陡峭 %.2f",
                    force.agitation, force.fatigue, force.sweetCenter, force.spec.steepBase)
                if debugReading:GetText() ~= debugText then debugReading:SetText(debugText) end
            else
                if debugReading:GetText() ~= "" then debugReading:SetText("") end
            end
        end
    end

    ---@param paused boolean
    function view:ShowPaused(paused)
        if paused then
            caption:SetText("已暂停 · 回到前台后继续")
        else
            caption:SetText(self.lastState == "moving" and "移动中" or "已锁定")
        end
    end

    return view
end

return View
