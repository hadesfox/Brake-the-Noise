-- 力度曲线条的自绘控件：背景、曲线折线、甜蜜点标记、游标。
-- 只在 Render 里读取模型，不推进模型状态，因此暂停时画面自然冻结。
local UI = require("urhox-libs/UI")
local ForceCurve = require("gameplay.ForceCurve")

local Strip = UI.Widget:Extend("ForceCurveStrip")

---@class ForceCurveStripProps : WidgetProps
---@field model? ForceCurveModel 曲线模型，Render 时读取
---@field samples? number 采样点数

---@class ForceCurveStrip : Widget
---@field props ForceCurveStripProps
---@field model_ ForceCurveModel?

---@param props ForceCurveStripProps
function Strip:Init(props)
    props = props or {}
    props.height = props.height or 320
    props.width = props.width or "100%"
    props.backgroundColor = props.backgroundColor or { 244, 247, 248, 255 }
    props.borderRadius = props.borderRadius or 8
    props.overflow = "hidden"
    props.pointerEvents = props.pointerEvents or "none"
    props.samples = props.samples or 48
    UI.Widget.Init(self, props)
    self.model_ = props.model
end

---@param model ForceCurveModel?
function Strip:SetModel(model)
    self.model_ = model
end

---@param nvg NVGContextWrapper
function Strip:Render(nvg)
    self:RenderFullBackground(nvg)
    local model = self.model_
    if not model then return end
    local l = self:GetAbsoluteLayout()
    local padX, padTop, padBottom = 10, 12, 22
    local innerW = l.w - padX * 2
    local innerH = l.h - padTop - padBottom
    if innerW <= 0 or innerH <= 0 then return end
    local function mapX(x) return l.x + padX + x * innerW end
    local function mapY(force) return l.y + padTop + (1 - force) * innerH end
    local spec = model.spec

    -- 低平区底色：它的宽度就是暴躁与疲劳真正改变的东西。
    local flatHalf = ForceCurve.Evaluate(spec, model.sweetSpot, model.sweetSpot,
        model.agitation, model.fatigue)
    nvgBeginPath(nvg)
    nvgRect(nvg, mapX(model.sweetSpot - flatHalf), l.y + padTop,
        flatHalf * 2 * innerW, innerH)
    nvgFillColor(nvg, nvgRGBA(23, 167, 176, 28))
    nvgFill(nvg)

    -- 曲线折线
    local samples = math.max(2, math.floor(self.props.samples or 48))
    nvgBeginPath(nvg)
    for index = 0, samples do
        local x = index / samples
        local force = ForceCurve.Evaluate(spec, x, model.sweetSpot, model.agitation, model.fatigue)
        if index == 0 then
            nvgMoveTo(nvg, mapX(x), mapY(force))
        else
            nvgLineTo(nvg, mapX(x), mapY(force))
        end
    end
    nvgStrokeColor(nvg, nvgRGBA(46, 74, 92, 235))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 甜蜜点：低平区中心，也就是本轮曲线的最低点。
    local sweetForce = ForceCurve.Evaluate(spec, model.sweetSpot, model.sweetSpot,
        model.agitation, model.fatigue)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, mapX(model.sweetSpot), mapY(sweetForce) + 3)
    nvgLineTo(nvg, mapX(model.sweetSpot), l.y + l.h - padBottom + 6)
    nvgStrokeColor(nvg, nvgRGBA(120, 132, 140, 170))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 游标
    local cursorX = mapX(model.x)
    nvgBeginPath(nvg)
    nvgRect(nvg, cursorX - 1.5, l.y + padTop, 3, innerH)
    nvgFillColor(nvg, nvgRGBA(230, 75, 70, model.moving and 235 or 255))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, cursorX - 4, mapY(model.force) - 4, 8, 8)
    nvgFillColor(nvg, nvgRGBA(230, 75, 70, 255))
    nvgFill(nvg)
end

return Strip
