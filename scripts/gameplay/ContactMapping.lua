-- P1.2e 纯 Lua 映射：把两种几何覆盖率变成载荷集中系数与接触效率。
--
-- 结构已由作者确认：A有效 = A集中(r踏板) × E传导(r鞋底)。
-- 两个输入来自 Landing.Contact 的同一次真实交集，没有独立的鞋种倍率：
--   r踏板 = 交集面积 / 踏板面积     → A集中，覆盖越少越集中，有有限上限
--   r鞋底 = 交集面积 / 鞋底总面积   → E传导，充分接触接近一，部分踩空时降低
--
-- 这样"小鞋底充分踩中"（r踏板 高、r鞋底 高）与"大鞋底大部分踩空"（r踏板 低、r鞋底 低）
-- 不会得到同一个危险结论：前者集中但传导好，后者集中高却传导差。
--
-- 检测目的：给出 A有效，供 T = F × L × A有效 × K姿势 使用。
-- 边界：零接触不进入载荷计算，由调用方先看 hasContact，这里不产生"踩空也算集中"的结果。

---@class ContactMappingConfig
---@field concentrateMin number r踏板 为 0 时的 A集中
---@field concentrateMax number r踏板 为 1 时的 A集中，有限上限
---@field concentrateCurve number 集中曲线指数，大于 0
---@field conductionFloor number r鞋底 为 0 时的 E传导
---@field conductionFull number r鞋底 为 1 时的 E传导，通常为一
---@field conductionCurve number 传导曲线指数，大于 0
---@field conductionSoftStart number 极小接触的软化起点，低于它 E 快速衰减

---@class ContactMappingResult
---@field concentrate number A集中
---@field conduction number E传导
---@field effective number A有效 = A集中 × E传导

local ContactMapping = {}

---@param value any
---@return boolean
local function IsFinite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

---@param config ContactMappingConfig
local function ValidateConfig(config)
    assert(type(config) == "table", "接触映射配置必须为 table")
    local names = {
        "concentrateMin", "concentrateMax", "concentrateCurve",
        "conductionFloor", "conductionFull", "conductionCurve", "conductionSoftStart",
    }
    for _, name in ipairs(names) do
        assert(IsFinite(config[name]), "接触映射字段必须是有限数值：" .. name)
    end
    assert(config.concentrateMin > 0, "A集中 下限必须为正，避免零接触以外的除零")
    assert(config.concentrateMax >= config.concentrateMin, "A集中 上限不能低于下限")
    assert(config.concentrateCurve > 0, "集中曲线指数必须大于零")
    assert(config.conductionFloor >= 0 and config.conductionFull > 0, "E传导 必须非负且有正上限")
    assert(config.conductionFull >= config.conductionFloor, "E传导 上限不能低于下限")
    assert(config.conductionCurve > 0, "传导曲线指数必须大于零")
    assert(config.conductionSoftStart >= 0 and config.conductionSoftStart < 1,
        "极小接触软化起点必须在 [0,1)")
end

---@param ratio number
---@return number
local function ClampUnit(ratio)
    return math.max(0, math.min(1, ratio))
end

-- A集中：r踏板 越小越集中。曲线指数大于一时，只有真正小的接触面才明显放大。
---@param config ContactMappingConfig
---@param pedalCoverage number
---@return number
function ContactMapping.Concentrate(config, pedalCoverage)
    ValidateConfig(config)
    local ratio = ClampUnit(pedalCoverage)
    local deficit = 1 - ratio
    local weight = deficit ^ config.concentrateCurve
    return config.concentrateMin + (config.concentrateMax - config.concentrateMin) * weight
end

-- E传导：r鞋底 高时接近满值；低于软化起点后额外衰减，表达"大部分踩空"。
---@param config ContactMappingConfig
---@param shoeCoverage number
---@return number
function ContactMapping.Conduction(config, shoeCoverage)
    ValidateConfig(config)
    local ratio = ClampUnit(shoeCoverage)
    local weight = ratio ^ config.conductionCurve
    local conduction = config.conductionFloor
        + (config.conductionFull - config.conductionFloor) * weight
    if config.conductionSoftStart > 0 and ratio < config.conductionSoftStart then
        local softness = ratio / config.conductionSoftStart
        conduction = conduction * softness
    end
    return math.max(0, conduction)
end

-- A有效：联合结构。零接触由调用方跳过，这里对零覆盖率返回下限乘积而不是抛出。
---@param config ContactMappingConfig
---@param pedalCoverage number
---@param shoeCoverage number
---@return ContactMappingResult
function ContactMapping.Evaluate(config, pedalCoverage, shoeCoverage)
    ValidateConfig(config)
    assert(IsFinite(pedalCoverage) and IsFinite(shoeCoverage), "覆盖率必须是有限数值")
    local concentrate = ContactMapping.Concentrate(config, pedalCoverage)
    local conduction = ContactMapping.Conduction(config, shoeCoverage)
    local effective = concentrate * conduction
    assert(IsFinite(effective), "A有效 溢出")
    return { concentrate = concentrate, conduction = conduction, effective = effective }
end

return ContactMapping
