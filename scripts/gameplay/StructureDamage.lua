-- 二态结构判定：未断裂累计隐藏损伤 / 断裂时制动力归零
-- 设计依据：方案A 第22章 + 实施计划 4.2 节
--
-- 输入：
--   torqueT: 游戏等效破坏载荷
--   durabilityEffective: M有效 = M剩余 × C温度(θ)
--   hiddenDamageBefore: 测试前隐藏损伤累计
--
-- 输出：
--   structureState: "intact" | "broken"
--   hiddenDamageAfter: 测试后隐藏损伤累计
--   actualPedalForce: 实际作用到制动通道的力（断裂时归零）

local StructureDamage = {}

--- 判定结构状态并计算隐藏损伤
---@param params table 输入参数
---@return table 输出结果
function StructureDamage.evaluate(params)
    local torqueT = params.torqueT or 0
    local durabilityEffective = params.durabilityEffective or 1000
    local hiddenDamageBefore = params.hiddenDamageBefore or 0
    local pedalForce = params.pedalForce or 0
    local conductionE = params.conductionE or 1.0

    -- 判定是否断裂
    local totalDamage = hiddenDamageBefore + torqueT
    local broken = totalDamage >= durabilityEffective

    -- 隐藏损伤累计（断裂后不再累计）
    local hiddenDamageAfter = broken and hiddenDamageBefore or totalDamage

    -- 结构状态
    local structureState = broken and "broken" or "intact"

    -- 实际制动通道力（断裂时归零）
    local actualPedalForce = broken and 0 or (pedalForce * conductionE)

    return {
        structureState = structureState,
        hiddenDamageAfter = hiddenDamageAfter,
        actualPedalForce = actualPedalForce,
        broken = broken,
    }
end

return StructureDamage
