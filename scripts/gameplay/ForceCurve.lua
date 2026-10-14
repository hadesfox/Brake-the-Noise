-- P1.3f 纯 Lua 模型：力度心理曲线、游标运动学与牛顿力度。
--
-- 曲线外形固定为"两端大、中间小"：甜蜜区是整条的最低力度段，也是从容控制的理想区，
-- 不是断裂奖励区。命中不保证断裂，区外也不自动失败。
--
--   F(N)
--   1612 |╲                                    ╱|   ← 两端为本状态下最高力度
--        | ╲__________________________________╱ |   ← 甜蜜区，宽度只被暴躁收窄
--     80 |______________________________________|
--        0        甜蜜区中心（每轮漂移）        1  x
--
-- 已确认口径（作者 2026-10-14）：
--   · 中心基准 0.50；最大漂移 ±0.18，即全条的 ±18 个百分点。
--   · 区间按全宽定义，范围 0.10～0.04（半宽 0.05～0.02）；仅暴躁收窄。
--   · 人的疲劳减弱可用力量，不抬高最低段、不收窄也不放宽甜蜜区、不延迟按停。
--   · 暴躁压缩低力度占比、扩大高力度占比并收窄甜蜜区，与疲劳独立记录。
--   · 疲劳与暴躁都参与中心漂移，种子决定方向，总幅度不超过 ±18 个百分点。
--   · 甜蜜区到两端连续渐变，离开区间一点不会直接跳到最大值。
--   · 力度 F 在 80～1612 N，超出上限截断；不锁定后随机压回数值。
--
-- 计算结构：意图力度 → 疲劳力量衰减 → F（80～1612 N 截断）。
-- 映射强度、渐变形状与抖动/变速幅度仍待作者给值，开发值只在 config/Demo.lua。

---@class ForceCurveSpec
---@field cursorSpeed number 基础扫速，归一化 x/秒
---@field intentLow number 甜蜜区中心的最低意图力度，牛顿
---@field intentHigh number 两端的最高意图力度，牛顿
---@field forceMin number F 截断下限，牛顿
---@field forceMax number F 截断上限，牛顿
---@field rampWidth number 抬升归一宽度：甜蜜区边缘往外多宽升到端点
---@field steepBase number 基础陡峭指数
---@field steepAgitation number 暴躁到 1 时增加的陡峭指数
---@field sweetBase number 甜蜜区中心基准位置
---@field sweetDriftMax number 每轮中心漂移的最大幅度，全条占比
---@field agitationDriftWeight number 暴躁对漂移幅度的权重
---@field fatigueDriftWeight number 疲劳对漂移幅度的权重
---@field sweetHalfMax number 甜蜜区最大半宽（全宽 10% → 0.05）
---@field sweetHalfMin number 甜蜜区最小半宽（全宽 4% → 0.02）
---@field sweetNarrowAgitation number 暴躁到 1 时的收窄比例，零到一
---@field fatigueForceCut number 疲劳到 1 时减弱可用力量的比例，零到一
---@field jitterAmp number 暴躁到 1 时的游标抖动幅度
---@field jitterFreq1 number 抖动主频，赫兹
---@field jitterFreq2 number 抖动次频，赫兹
---@field speedAgitation number 暴躁到 1 时的扫速加成比例
---@field speedFatigue number 疲劳到 1 时的扫速衰减比例，须小于一

---@class ForceRecord
---@field x number 条内位置
---@field force number 实际踩踏力度 F，牛顿，已按疲劳衰减并截断
---@field intentForce number 意图力度，牛顿，未做疲劳衰减
---@field sweetCenter number 本轮甜蜜区中心
---@field sweetHalf number 本轮甜蜜区半宽
---@field steepness number 本轮陡峭指数
---@field agitation number
---@field fatigue number
---@field elapsed number 本轮有效运动时间，不含暂停和历史轮次
---@field seed number 初始种子，不是已推进的 LCG 状态
---@field source string

---@class ForceCurveModel
---@field spec ForceCurveSpec 配置的深拷贝
---@field seed number
---@field agitation number
---@field fatigue number
---@field sweetCenter number
---@field x number
---@field force number
---@field intentForce number
---@field moving boolean
---@field elapsed number
---@field speed number
---@field records ForceRecord[]
---@field randomState_ number
---@field elapsedCorrection_ number
---@field phase_ number 累计相位，跨轮连续
---@field phaseStart_ number 本轮起点相位
---@field jitterPhase1_ number
---@field jitterPhase2_ number
local ForceCurve = {}
ForceCurve.__index = ForceCurve

local LCG_MODULUS = 4294967296
local TAU = math.pi * 2

---@param value any
---@return boolean
local function IsFinite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

---@param value any
---@param description string
---@return number
local function UnitRange(value, description)
    assert(IsFinite(value) and value >= 0 and value <= 1, description .. "必须在 [0,1]")
    return value
end

---@param spec ForceCurveSpec
local function ValidateSpec(spec)
    assert(type(spec) == "table", "力度曲线配置必须为 table")
    local numbers = {
        "cursorSpeed", "intentLow", "intentHigh", "forceMin", "forceMax",
        "rampWidth", "steepBase", "steepAgitation",
        "sweetBase", "sweetDriftMax", "agitationDriftWeight", "fatigueDriftWeight",
        "sweetHalfMax", "sweetHalfMin", "sweetNarrowAgitation", "fatigueForceCut",
        "jitterAmp", "jitterFreq1", "jitterFreq2", "speedAgitation", "speedFatigue",
    }
    for _, name in ipairs(numbers) do
        assert(IsFinite(spec[name]), "力度曲线字段必须是有限数值：" .. name)
    end
    assert(spec.cursorSpeed > 0, "基础扫速必须大于零")
    assert(spec.forceMin > 0, "力度下限必须为正")
    assert(spec.forceMax >= spec.forceMin, "力度上限不能低于下限")
    assert(spec.intentLow >= 0, "最低意图力度不能为负")
    assert(spec.intentHigh >= spec.intentLow, "最高意图力度不能低于最低意图力度")
    assert(spec.rampWidth > 0 and spec.rampWidth <= 1, "抬升归一宽度必须在 (0,1]")
    assert(spec.steepBase >= 1, "基础陡峭指数不能小于一")
    assert(spec.steepAgitation >= 0, "暴躁陡峭加成不能为负")
    UnitRange(spec.sweetBase, "甜蜜区中心基准")
    assert(spec.sweetDriftMax >= 0 and spec.sweetDriftMax <= 0.5, "最大漂移必须在 [0,0.5]")
    assert(spec.agitationDriftWeight >= 0 and spec.fatigueDriftWeight >= 0, "漂移权重不能为负")
    assert(spec.sweetHalfMin > 0, "甜蜜区最小半宽必须为正")
    assert(spec.sweetHalfMax >= spec.sweetHalfMin, "甜蜜区最大半宽不能小于最小半宽")
    UnitRange(spec.sweetNarrowAgitation, "暴躁收窄比例")
    UnitRange(spec.fatigueForceCut, "疲劳减力比例")
    assert(spec.jitterAmp >= 0, "抖动幅度不能为负")
    assert(spec.jitterFreq1 > 0 and spec.jitterFreq2 > 0, "抖动频率必须大于零")
    assert(spec.speedAgitation >= 0, "扫速加成不能为负")
    UnitRange(spec.speedFatigue, "扫速衰减比例")
    -- 疲劳拉满时扫速仍须为正，否则游标会停住、本轮无法按停。
    assert(spec.cursorSpeed * (1 - spec.speedFatigue) > 0, "疲劳拉满后扫速必须仍大于零")
    -- 甜蜜区中心必须给最宽半宽与最大漂移留出余量，否则区间会被挤到条外。
    local margin = spec.sweetHalfMax
    assert(spec.sweetBase - spec.sweetDriftMax >= margin
        and spec.sweetBase + spec.sweetDriftMax <= 1 - margin,
        "甜蜜区中心基准与最大漂移没有给最宽半宽留出余量")
end

---@param spec ForceCurveSpec
---@return ForceCurveSpec
local function CopySpec(spec)
    return {
        cursorSpeed = spec.cursorSpeed,
        intentLow = spec.intentLow,
        intentHigh = spec.intentHigh,
        forceMin = spec.forceMin,
        forceMax = spec.forceMax,
        rampWidth = spec.rampWidth,
        steepBase = spec.steepBase,
        steepAgitation = spec.steepAgitation,
        sweetBase = spec.sweetBase,
        sweetDriftMax = spec.sweetDriftMax,
        agitationDriftWeight = spec.agitationDriftWeight,
        fatigueDriftWeight = spec.fatigueDriftWeight,
        sweetHalfMax = spec.sweetHalfMax,
        sweetHalfMin = spec.sweetHalfMin,
        sweetNarrowAgitation = spec.sweetNarrowAgitation,
        fatigueForceCut = spec.fatigueForceCut,
        jitterAmp = spec.jitterAmp,
        jitterFreq1 = spec.jitterFreq1,
        jitterFreq2 = spec.jitterFreq2,
        speedAgitation = spec.speedAgitation,
        speedFatigue = spec.speedFatigue,
    }
end

---@param record ForceRecord
---@return ForceRecord
local function CopyRecord(record)
    return {
        x = record.x, force = record.force, intentForce = record.intentForce,
        sweetCenter = record.sweetCenter, sweetHalf = record.sweetHalf,
        steepness = record.steepness, agitation = record.agitation, fatigue = record.fatigue,
        elapsed = record.elapsed, seed = record.seed, source = record.source,
    }
end

---@param phase number
---@return number
local function PingPong(phase)
    local folded = phase % 2
    return folded <= 1 and folded or 2 - folded
end

-- 甜蜜区半宽：基准取全宽上限，只有暴躁收窄；疲劳不参与宽度。
---@param spec ForceCurveSpec
---@param agitation number
---@return number
function ForceCurve.SweetHalf(spec, agitation)
    local narrowed = spec.sweetHalfMax * (1 - spec.sweetNarrowAgitation * agitation)
    return math.max(spec.sweetHalfMin, math.min(spec.sweetHalfMax, narrowed))
end

-- 疲劳力量衰减：只减弱可用力量，不抬高最低段、不改甜蜜区宽度。
---@param spec ForceCurveSpec
---@param intentForce number
---@param fatigue number
---@return number
function ForceCurve.FatiguedForce(spec, intentForce, fatigue)
    local force = intentForce * (1 - spec.fatigueForceCut * fatigue)
    return math.max(spec.forceMin, math.min(spec.forceMax, force))
end

-- 曲线求值：返回实际力度、甜蜜区半宽与陡峭指数，便于记录与调试。
-- 抬升量按固定水平宽度 rampWidth 归一，所以甜蜜区一变窄，两侧立刻更陡；
-- 陡峭指数取倒数做幂，指数越大越早抬起来（也就是越陡）。
---@param spec ForceCurveSpec
---@param x number
---@param sweetCenter number
---@param agitation number
---@param fatigue number
---@return number force
---@return number sweetHalf
---@return number steepness
function ForceCurve.Evaluate(spec, x, sweetCenter, agitation, fatigue)
    assert(IsFinite(x), "条内位置必须是有限数值")
    local sweetHalf = ForceCurve.SweetHalf(spec, agitation)
    local steepness = spec.steepBase + spec.steepAgitation * agitation
    local distance = math.abs(x - sweetCenter)
    ---@type number
    local t = 0
    if distance > sweetHalf then
        t = math.min(1, (distance - sweetHalf) / spec.rampWidth)
    end
    local shape = t ^ (1 / steepness)
    local intentForce = spec.intentLow + (spec.intentHigh - spec.intentLow) * shape
    local force = ForceCurve.FatiguedForce(spec, intentForce, fatigue)
    return force, sweetHalf, steepness
end

-- 意图力度单独可查，供档案区分"想踩多重"和"实际踩多重"。
---@param spec ForceCurveSpec
---@param x number
---@param sweetCenter number
---@param agitation number
---@return number
function ForceCurve.IntentForce(spec, x, sweetCenter, agitation)
    local sweetHalf = ForceCurve.SweetHalf(spec, agitation)
    local steepness = spec.steepBase + spec.steepAgitation * agitation
    local distance = math.abs(x - sweetCenter)
    ---@type number
    local t = 0
    if distance > sweetHalf then
        t = math.min(1, (distance - sweetHalf) / spec.rampWidth)
    end
    return spec.intentLow + (spec.intentHigh - spec.intentLow) * (t ^ (1 / steepness))
end

---@param spec ForceCurveSpec
---@param seed number
---@return ForceCurveModel
function ForceCurve.Create(spec, seed)
    ValidateSpec(spec)
    assert(IsFinite(seed) and seed == math.floor(seed) and seed >= 0 and seed < LCG_MODULUS,
        "种子必须是 [0,2^32) 的整数")
    local model = setmetatable({}, ForceCurve)
    model:init(spec, seed)
    return model
end

---@param spec ForceCurveSpec
---@param seed number
function ForceCurve:init(spec, seed)
    self.spec = CopySpec(spec)
    self.seed = seed
    self.randomState_ = seed
    self.agitation, self.fatigue = 0, 0
    self.sweetCenter = spec.sweetBase
    self.x, self.force, self.intentForce = 0, 0, 0
    self.moving = false
    self.elapsed, self.elapsedCorrection_ = 0, 0
    self.phase_, self.phaseStart_ = 0, 0
    self.records = {}
    self.jitterPhase1_ = self:NextRandom_() * TAU
    self.jitterPhase2_ = self:NextRandom_() * TAU
    self.speed = self:SpeedFor_(self.agitation, self.fatigue)
    self:Start()
end

---@return number
function ForceCurve:NextRandom_()
    -- 32 位 LCG：乘积小于 2^53，Lua integer 和 double 都能准确计算，不碰 math.random。
    self.randomState_ = (1664525 * self.randomState_ + 1013904223) % LCG_MODULUS
    return self.randomState_ / LCG_MODULUS
end

---@param agitation number
---@param fatigue number
---@return number
function ForceCurve:SpeedFor_(agitation, fatigue)
    return self.spec.cursorSpeed * (1 + self.spec.speedAgitation * agitation)
        * (1 - self.spec.speedFatigue * fatigue)
end

-- 每轮重新抽中心漂移：幅度由疲劳与暴躁共同决定，方向由种子决定。
-- 漂移在本轮开始时一次确定，本轮不追逐；总幅度不超过 ±18 个百分点。
---@return number
function ForceCurve:NextSweetCenter_()
    local spec = self.spec
    local combined = math.min(1,
        spec.agitationDriftWeight * self.agitation + spec.fatigueDriftWeight * self.fatigue)
    local magnitude = spec.sweetDriftMax * combined
    local direction = self:NextRandom_() < 0.5 and -1 or 1
    local margin = spec.sweetHalfMax
    local center = spec.sweetBase + direction * magnitude
    self.sweetCenter = math.max(margin, math.min(1 - margin, center))
    return self.sweetCenter
end

---@param elapsed number
---@return number
function ForceCurve:PositionAt_(elapsed)
    local base = PingPong(self.phaseStart_ + self.speed * elapsed)
    -- 抖动幅度为零时两个正弦项相乘仍得零，不需要分支，也就没有整数字面量。
    local amplitude = self.spec.jitterAmp * self.agitation
    local jitter = amplitude * (0.65 * math.sin(TAU * self.spec.jitterFreq1 * elapsed + self.jitterPhase1_)
        + 0.35 * math.sin(TAU * self.spec.jitterFreq2 * elapsed + self.jitterPhase2_))
    return math.max(0, math.min(1, base + jitter))
end

---@param dt number
function ForceCurve:Update(dt)
    assert(IsFinite(dt) and dt >= 0, "dt 必须为有限非负数")
    if not self.moving or dt == 0 then return end
    -- 补偿时间累加；位置与抖动都按本轮绝对时间求值，不逐帧累加坐标。
    local adjusted = dt - self.elapsedCorrection_
    local elapsed = self.elapsed + adjusted
    assert(IsFinite(elapsed), "累计运动时间溢出")
    self.elapsedCorrection_ = (elapsed - self.elapsed) - adjusted
    self.elapsed = elapsed
    self.phase_ = self.phaseStart_ + self.speed * elapsed
    self.x = self:PositionAt_(elapsed)
    self.intentForce = ForceCurve.IntentForce(self.spec, self.x, self.sweetCenter, self.agitation)
    self.force = ForceCurve.FatiguedForce(self.spec, self.intentForce, self.fatigue)
end

-- 暴躁与疲劳是两个独立变量，不合并成单一状态值；只允许在未运动时设置。
---@param agitation number
---@param fatigue number
---@return boolean
function ForceCurve:SetState(agitation, fatigue)
    if self.moving then return false end
    UnitRange(agitation, "暴躁值")
    UnitRange(fatigue, "疲劳值")
    self.agitation, self.fatigue = agitation, fatigue
    self.speed = self:SpeedFor_(agitation, fatigue)
    self.intentForce = ForceCurve.IntentForce(self.spec, self.x, self.sweetCenter, self.agitation)
    self.force = ForceCurve.FatiguedForce(self.spec, self.intentForce, self.fatigue)
    return true
end

---@param source string?
---@return ForceRecord?
function ForceCurve:Lock(source)
    if not self.moving then return nil end
    assert(source == nil or (type(source) == "string" and source ~= ""), "输入来源必须是非空字符串")
    local force, sweetHalf, steepness =
        ForceCurve.Evaluate(self.spec, self.x, self.sweetCenter, self.agitation, self.fatigue)
    local intentForce = ForceCurve.IntentForce(self.spec, self.x, self.sweetCenter, self.agitation)
    ---@type ForceRecord
    local record = {
        x = self.x, force = force, intentForce = intentForce,
        sweetCenter = self.sweetCenter, sweetHalf = sweetHalf, steepness = steepness,
        agitation = self.agitation, fatigue = self.fatigue,
        elapsed = self.elapsed, seed = self.seed, source = source or "unknown",
    }
    self.moving = false
    self.force = force
    self.intentForce = intentForce
    self.records[#self.records + 1] = record
    -- 返回另一份快照，外部修改返回值不会改写已存历史。
    return CopyRecord(record)
end

-- 初次 Create 已调用 Start；已 moving 时调用无副作用。
-- 新一轮重置 elapsed、重新抽中心漂移，保留种子流、累计相位与 records。
---@return boolean
function ForceCurve:Start()
    if self.moving then return false end
    self.speed = self:SpeedFor_(self.agitation, self.fatigue)
    self:NextSweetCenter_()
    self.elapsed, self.elapsedCorrection_ = 0, 0
    self.phaseStart_ = self.phase_
    self.moving = true
    self.x = self:PositionAt_(0)
    self.intentForce = ForceCurve.IntentForce(self.spec, self.x, self.sweetCenter, self.agitation)
    self.force = ForceCurve.FatiguedForce(self.spec, self.intentForce, self.fatigue)
    return true
end

---@return boolean
function ForceCurve:Resume()
    return self:Start()
end

return ForceCurve
