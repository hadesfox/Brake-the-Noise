-- P1.2e 纯 Lua 回归：A有效 = A集中(r踏板) × E传导(r鞋底) 的联合结构。
-- 只使用测试 fixtures，不读取 Demo 或正式游戏配置。
local ContactMapping = require("gameplay.ContactMapping")
local Tests = {}

---@return ContactMappingConfig
local function Fixture()
    return {
        concentrateMin = 1.0,
        concentrateMax = 2.6,
        concentrateCurve = 1.4,
        conductionFloor = 0.15,
        conductionFull = 1.0,
        conductionCurve = 0.9,
        conductionSoftStart = 0.25,
    }
end

---@param a number
---@param b number
---@return boolean
local function Near(a, b)
    return math.abs(a - b) <= 0.000000001
end

---@return integer
function Tests.Run()
    local count = 0
    ---@param condition boolean
    ---@param description string
    local function Check(condition, description)
        assert(condition, "[接触映射失败] " .. description)
        count = count + 1
    end

    local config = Fixture()
    -- A集中：踏板覆盖越少越集中，但有有限上限，不出现无限放大。
    Check(Near(ContactMapping.Concentrate(config, 1), config.concentrateMin),
        "踏板全覆盖时 A集中 取下限")
    Check(Near(ContactMapping.Concentrate(config, 0), config.concentrateMax),
        "踏板零覆盖时 A集中 取有限上限")
    local small = ContactMapping.Concentrate(config, 0.05)
    local mid = ContactMapping.Concentrate(config, 0.5)
    local large = ContactMapping.Concentrate(config, 1)
    Check(small > mid and mid > large, "覆盖越少 A集中 越大，方向保持")
    Check(small <= config.concentrateMax, "A集中 有有限上限，不是无上限 1/r")
    Check(ContactMapping.Concentrate(config, -1) == config.concentrateMax
        and ContactMapping.Concentrate(config, 2) == config.concentrateMin, "越界覆盖率被钳制")

    -- E传导：充分接触接近满值，接触减少时降低，极小接触额外软化。
    Check(Near(ContactMapping.Conduction(config, 1), config.conductionFull),
        "鞋底充分接触时 E传导 接近满值")
    Check(Near(ContactMapping.Conduction(config, 0), 0), "鞋底零接触时 E传导 为零")
    local full = ContactMapping.Conduction(config, 1)
    local partial = ContactMapping.Conduction(config, 0.6)
    local sliver = ContactMapping.Conduction(config, 0.05)
    Check(full > partial and partial > sliver, "接触越少 E传导 越低")
    Check(sliver >= 0 and full <= 1, "E传导 有界在零到一")
    local belowSoft = ContactMapping.Conduction(config, 0.2)
    local baseCurve = config.conductionFloor
        + (config.conductionFull - config.conductionFloor) * (0.2 ^ config.conductionCurve)
    Check(belowSoft < baseCurve, "低于软化起点时额外衰减，表达大部分踩空")

    -- 关键区别：小鞋底充分踩中 vs 大鞋底大部分踩空。
    -- 小鞋底充分踩中：踏板覆盖低（集中高）且鞋底接触高（传导好）。
    local heel = ContactMapping.Evaluate(config, 0.2, 0.98)
    -- 大鞋底一角踩中：踏板覆盖低（集中高）但鞋底接触极低（传导差）。
    local toeEdge = ContactMapping.Evaluate(config, 0.2, 0.05)
    Check(heel.concentrate > 1 and toeEdge.concentrate > 1, "两种小覆盖都有集中效果")
    Check(Near(heel.concentrate, toeEdge.concentrate), "同一踏板覆盖率给出同一 A集中")
    Check(heel.conduction > toeEdge.conduction, "充分踩中的传导高于部分踩空")
    Check(heel.effective > toeEdge.effective,
        "小鞋底充分踩中的 A有效 高于大鞋底一角踩空，两者不同结论")
    Check(toeEdge.effective < heel.effective, "部分踩空不会因为集中而变成最高危险输入")

    -- 联合结构：A有效 就是两个系数的乘积，不额外重复相乘。
    local combined = ContactMapping.Evaluate(config, 0.35, 0.7)
    Check(Near(combined.effective, combined.concentrate * combined.conduction),
        "A有效 = A集中 × E传导")
    Check(combined.effective <= config.concentrateMax * config.conductionFull,
        "A有效 不超过两个上限的乘积")

    -- 同一落点换鞋：输入是真实几何覆盖率，结果来自几何而不是鞋种倍率。
    local slim = ContactMapping.Evaluate(config, 0.9, 0.95)
    local wide = ContactMapping.Evaluate(config, 0.4, 0.35)
    Check(slim.effective ~= wide.effective, "同一落点换鞋给出不同 A有效")
    Check(slim.conduction > wide.conduction, "覆盖充分的鞋传导更好")

    -- 零接触由调用方跳过；这里不产生"踩空也算集中"的结果。
    local empty = ContactMapping.Evaluate(config, 0, 0)
    Check(empty.conduction == 0 and empty.effective == 0, "零接触的 A有效 为零")

    ---@param change fun(config: ContactMappingConfig)
    ---@param description string
    local function RejectConfig(change, description)
        local bad = Fixture()
        change(bad)
        assert(not pcall(ContactMapping.Evaluate, bad, 0.5, 0.5), "[接触映射失败] " .. description)
        count = count + 1
    end
    RejectConfig(function(c) c.concentrateMin = 0 end, "拒绝零 A集中 下限")
    RejectConfig(function(c) c.concentrateMax = 0.5 end, "拒绝上限低于下限")
    RejectConfig(function(c) c.concentrateCurve = 0 end, "拒绝零集中曲线指数")
    RejectConfig(function(c) c.conductionFloor = -1 end, "拒绝负 E传导 下限")
    RejectConfig(function(c) c.conductionFull = 0 end, "拒绝零 E传导 上限")
    RejectConfig(function(c) c.conductionCurve = 0 end, "拒绝零传导曲线指数")
    RejectConfig(function(c) c.conductionSoftStart = 1 end, "拒绝越界软化起点")
    RejectConfig(function(c) c.conductionSoftStart = -1 end, "拒绝负软化起点")
    RejectConfig(function(c) c.concentrateMin = 0 / 0 end, "拒绝 NaN 配置")
    Check(not pcall(ContactMapping.Evaluate, config, 0 / 0, 0.5), "拒绝 NaN 覆盖率")

    print("[接触映射验证] PASS，纯 Lua 集中/传导/联合断言数=" .. count)
    return count
end

return Tests
