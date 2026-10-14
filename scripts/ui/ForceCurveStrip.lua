-- 力度曲线的自绘控件：背景、曲线折线、甜蜜区底色、中心标记、游标。
-- 只在 Render 里读取模型，不推进模型状态，因此暂停时画面自然冻结。
-- 正式局内不显示暴躁/疲劳/甜蜜区中心等隐藏数值，这里只画形状与游标。
local UI = require("urhox-libs/UI")
local ForceCurve = require("gameplay.ForceCurve")

local Strip = UI.Widget:Extend("ForceCurveStrip")

---@class ForceCurveStripProps : WidgetProps
---@field model? ForceCurveModel 曲线模型，Render 时读取
---@field samples? number 采样点数
---@field showSweetBand? boolean 是否画出甜蜜区底色，默认画

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
    if props.showSweetBand == nil then props.showSweetBand = true end
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
    local function mapY(force)
        -- 纵向按 F 的截断范围映射，两端就是本状态的最高力度。
        local span = model.spec.forceMax - model.spec.forceMin
        if span <= 0 then return l.y + padTop + innerH end
        local normalized = (force - model.spec.forceMin) / span
        return l.y + padTop + (1 - math.max(0, math.min(1, normalized))) * innerH
    end
    local spec = model.spec

    -- 甜蜜区底色：它的宽度就是暴躁真正改变的东西；疲劳不参与。
    if self.props.showSweetBand then
        local sweetHalf = ForceCurve.SweetHalf(spec, model.agitation)
        nvgBeginPath(nvg)
        nvgRect(nvg, mapX(model.sweetCenter - sweetHalf), l.y + padTop,
            sweetHalf * 2 * innerW, innerH)
        nvgFillColor(nvg, nvgRGBA(23, 167, 176, 28))
        nvgFill(nvg)
    end

    -- 曲线折线
    local samples = math.max(2, math.floor(self.props.samples or 48))
    nvgBeginPath(nvg)
    for index = 0, samples do
        local x = index / samples
        local force = ForceCurve.Evaluate(spec, x, model.sweetCenter, model.agitation, model.fatigue)
        if index == 0 then
            nvgMoveTo(nvg, mapX(x), mapY(force))
        else
            nvgLineTo(nvg, mapX(x), mapY(force))
        end
    end
    nvgStrokeColor(nvg, nvgRGBA(46, 74, 92, 235))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 中心标记：甜蜜区的中心，也是本轮曲线的最低点。
    local centerForce = ForceCurve.Evaluate(spec, model.sweetCenter, model.sweetCenter,
        model.agitation, model.fatigue)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, mapX(model.sweetCenter), mapY(centerForce) + 3)
    nvgLineTo(nvg, mapX(model.sweetCenter), l.y + l.h - padBottom + 6)
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
