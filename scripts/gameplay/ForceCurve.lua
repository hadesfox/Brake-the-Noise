-- P1.3 纯 Lua 模型：力度心理曲线与游标运动学。
-- 曲线外形固定为"两端大、中间小"；隐藏状态只改变低平区宽度、陡峭度、整体高度与甜蜜点位置。
-- 不依赖引擎、UI、正式参数或全局随机数；开发 Demo 提供全部业务配置。
--
-- 归一化约定：x 在 [0,1] 上表示条内位置，force 在 [0,1] 上表示归一化力度。
-- 甜蜜点是低平区中心，也是本曲线的最低点；游标在整条上来回扫。
--
--   force
--    1.0 |  ╲                                    ╱
--        |   ╲                                  ╱
--        |    ╲________________________________╱     ← 低平区，宽度随状态变
--    0.0 |__________________________________________
--        0          甜蜜点（每轮漂移）            1  x
--
-- 检测目的：按停时同时给出落点 x 与归一化力度 force，供本轮结算使用。
-- 边界：低平区半宽不得超出甜蜜点到两端的最小距离；力度钳制到 [0,1]；
--       游标位置钳制到 [0,1]，抖动不会把游标甩出条外。

---@class ForceCurveSpec
---@field cursorSpeed number 基础扫速，归一化 x/秒
---@field flatHalfBase number 低平区半宽基准
---@field flatLevel number 低平区最低力度
---@field peakLift number 端点相对低平区的抬升
---@field rampWidth number 抬升归一宽度：低平区边缘往外多宽升到端点
---@field steepBase number 基础陡峭指数
---@field steepAgitation number 暴躁到 1 时增加的陡峭指数
---@field flatNarrow number 暴躁到 1 时低平区半宽的缩减比例，零到一
---@field widenFatigue number 疲劳到 1 时低平区半宽的扩张比例
---@field liftFatigue number 疲劳到 1 时的整体上移量
---@field sweetBase number 甜蜜点基准位置
---@field sweetDrift number 甜蜜点每轮最大漂移半径
---@field jitterAmp number 暴躁到 1 时的游标抖动幅度
---@field jitterFreq1 number 抖动主频，赫兹
---@field jitterFreq2 number 抖动次频，赫兹
---@field speedAgitation number 暴躁到 1 时的扫速加成比例
---@field speedFatigue number 疲劳到 1 时的扫速衰减比例，须小于一

---@class ForceRecord
---@field x number
---@field force number
---@field sweetSpot number
---@field flatHalf number
---@field steepness number
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
---@field sweetSpot number
---@field x number
---@field force number
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
        "cursorSpeed", "flatHalfBase", "flatLevel", "peakLift", "rampWidth", "steepBase",
        "steepAgitation", "flatNarrow", "widenFatigue", "liftFatigue",
        "sweetBase", "sweetDrift", "jitterAmp", "jitterFreq1", "jitterFreq2",
        "speedAgitation", "speedFatigue",
    }
    for _, name in ipairs(numbers) do
        assert(IsFinite(spec[name]), "力度曲线字段必须是有限数值：" .. name)
    end
    assert(spec.cursorSpeed > 0, "基础扫速必须大于零")
    assert(spec.flatHalfBase > 0 and spec.flatHalfBase <= 0.5, "低平区半宽基准必须在 (0,0.5]")
    assert(spec.flatLevel >= 0, "低平区最低力度不能为负")
    assert(spec.peakLift > 0, "端点抬升必须大于零")
    assert(spec.rampWidth > 0 and spec.rampWidth <= 1, "抬升归一宽度必须在 (0,1]")
    assert(spec.flatLevel + spec.peakLift <= 1, "低平区加端点抬升不能超过归一化上限")
    assert(spec.steepBase >= 1, "基础陡峭指数不能小于一")
    assert(spec.steepAgitation >= 0, "暴躁陡峭加成不能为负")
    UnitRange(spec.flatNarrow, "暴躁缩减比例")
    assert(spec.widenFatigue >= 0, "疲劳扩张比例不能为负")
    assert(spec.liftFatigue >= 0, "疲劳上移量不能为负")
    assert(spec.flatLevel + spec.peakLift + spec.liftFatigue <= 1,
        "疲劳上移后不能超过归一化上限")
    UnitRange(spec.sweetBase, "甜蜜点基准位置")
    assert(spec.sweetDrift >= 0, "甜蜜点漂移半径不能为负")
    assert(spec.jitterAmp >= 0, "抖动幅度不能为负")
    assert(spec.jitterFreq1 > 0 and spec.jitterFreq2 > 0, "抖动频率必须大于零")
    assert(spec.speedAgitation >= 0, "扫速加成不能为负")
    UnitRange(spec.speedFatigue, "扫速衰减比例")
    -- 疲劳拉满时扫速仍须为正，否则游标会停住、本轮无法按停。
    assert(spec.cursorSpeed * (1 - spec.speedFatigue) > 0, "疲劳拉满后扫速必须仍大于零")
    -- 甜蜜点必须留出疲劳拉满时的低平区半宽，否则低平区会被挤到条外。
    local margin = spec.flatHalfBase * (1 + spec.widenFatigue)
    assert(margin <= 0.5, "低平区最宽时不能超过半条")
    assert(spec.sweetBase >= margin and spec.sweetBase <= 1 - margin,
        "甜蜜点基准位置没有给最宽低平区留出余量")
end

---@param spec ForceCurveSpec
---@return ForceCurveSpec
local function CopySpec(spec)
    return {
        cursorSpeed = spec.cursorSpeed,
        flatHalfBase = spec.flatHalfBase,
        flatLevel = spec.flatLevel,
        peakLift = spec.peakLift,
        rampWidth = spec.rampWidth,
        steepBase = spec.steepBase,
        steepAgitation = spec.steepAgitation,
        flatNarrow = spec.flatNarrow,
        widenFatigue = spec.widenFatigue,
        liftFatigue = spec.liftFatigue,
        sweetBase = spec.sweetBase,
        sweetDrift = spec.sweetDrift,
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
        x = record.x, force = record.force, sweetSpot = record.sweetSpot,
        flatHalf = record.flatHalf, steepness = record.steepness,
        agitation = record.agitation, fatigue = record.fatigue,
        elapsed = record.elapsed, seed = record.seed, source = record.source,
    }
end

---@param phase number
---@return number
local function PingPong(phase)
    local folded = phase % 2
    return folded <= 1 and folded or 2 - folded
end

-- 曲线求值：返回力度、低平区半宽与陡峭指数，便于记录与调试。
-- 抬升量按固定水平宽度 rampWidth 归一，所以低平区一变窄，两侧立刻更陡；
-- 陡峭指数取倒数做幂，指数越大越早抬起来（也就是越陡）。
---@param spec ForceCurveSpec
---@param x number
---@param sweetSpot number
---@param agitation number
---@param fatigue number
---@return number force
---@return number flatHalf
---@return number steepness
function ForceCurve.Evaluate(spec, x, sweetSpot, agitation, fatigue)
    assert(IsFinite(x), "条内位置必须是有限数值")
    local flatHalf = spec.flatHalfBase * (1 - spec.flatNarrow * agitation) * (1 + spec.widenFatigue * fatigue)
    flatHalf = math.max(0, math.min(flatHalf, math.min(sweetSpot, 1 - sweetSpot)))
    local steepness = spec.steepBase + spec.steepAgitation * agitation
    local distance = math.abs(x - sweetSpot)
    ---@type number
    local t = 0
    if distance > flatHalf then
        t = math.min(1, (distance - flatHalf) / spec.rampWidth)
    end
    local force = spec.liftFatigue * fatigue + spec.flatLevel + spec.peakLift * (t ^ (1 / steepness))
    return math.max(0, math.min(1, force)), flatHalf, steepness
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
    self.sweetSpot = spec.sweetBase
    self.x, self.force = 0, 0
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

-- 每轮重新抽甜蜜点：隐藏状态决定曲线形状，漂移决定"中间"这次在哪。
function ForceCurve:NextSweetSpot_()
    local spec = self.spec
    local margin = spec.flatHalfBase * (1 + spec.widenFatigue)
    local offset = (self:NextRandom_() * 2 - 1) * spec.sweetDrift
    local spot = spec.sweetBase + offset
    self.sweetSpot = math.max(margin, math.min(1 - margin, spot))
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
    self.force = ForceCurve.Evaluate(self.spec, self.x, self.sweetSpot, self.agitation, self.fatigue)
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
    self.force = ForceCurve.Evaluate(self.spec, self.x, self.sweetSpot, self.agitation, self.fatigue)
    return true
end

---@param source string?
---@return ForceRecord?
function ForceCurve:Lock(source)
    if not self.moving then return nil end
    assert(source == nil or (type(source) == "string" and source ~= ""), "输入来源必须是非空字符串")
    local force, flatHalf, steepness =
        ForceCurve.Evaluate(self.spec, self.x, self.sweetSpot, self.agitation, self.fatigue)
    ---@type ForceRecord
    local record = {
        x = self.x, force = force, sweetSpot = self.sweetSpot,
        flatHalf = flatHalf, steepness = steepness,
        agitation = self.agitation, fatigue = self.fatigue,
        elapsed = self.elapsed, seed = self.seed, source = source or "unknown",
    }
    self.moving = false
    self.force = force
    self.records[#self.records + 1] = record
    -- 返回另一份快照，外部修改返回值不会改写已存历史。
    return CopyRecord(record)
end

-- 初次 Create 已调用 Start；已 moving 时调用无副作用。
-- 新一轮重置 elapsed、重新抽甜蜜点，保留种子流、累计相位与 records。
---@return boolean
function ForceCurve:Start()
    if self.moving then return false end
    self.speed = self:SpeedFor_(self.agitation, self.fatigue)
    self:NextSweetSpot_()
    self.elapsed, self.elapsedCorrection_ = 0, 0
    self.phaseStart_ = self.phase_
    self.moving = true
    self.x = self:PositionAt_(0)
    self.force = ForceCurve.Evaluate(self.spec, self.x, self.sweetSpot, self.agitation, self.fatigue)
    return true
end

---@return boolean
function ForceCurve:Resume()
    return self:Start()
end

return ForceCurve
