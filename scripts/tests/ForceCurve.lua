-- P1.3f 纯 Lua 回归：心理曲线的形状、甜蜜区宽度、疲劳减力、合成漂移与牛顿力度。
-- 只使用测试 fixtures，不读取 Demo 或正式游戏配置。
local ForceCurve = require("gameplay.ForceCurve")
local Tests = {}

---@return ForceCurveSpec
local function Fixture()
    return {
        cursorSpeed = 0.6,
        intentLow = 120,
        intentHigh = 1600,
        forceMin = 80,
        forceMax = 1612,
        rampWidth = 0.34,
        steepBase = 1.6,
        steepAgitation = 2.4,
        sweetBase = 0.5,
        sweetDriftMax = 0.18,
        agitationDriftWeight = 1.0,
        fatigueDriftWeight = 0.6,
        sweetHalfMax = 0.05,
        sweetHalfMin = 0.02,
        sweetNarrowAgitation = 0.6,
        fatigueForceCut = 0.35,
        jitterAmp = 0.04,
        jitterFreq1 = 5.5,
        jitterFreq2 = 13.0,
        speedAgitation = 0.5,
        speedFatigue = 0.3,
    }
end

---@param a number
---@param b number
---@return boolean
local function Near(a, b)
    return math.abs(a - b) <= 0.000000001
end

-- 曲线两端与最低点都是牛顿值；变的只是"从甜蜜区升到端点有多快"。
---@param spec ForceCurveSpec
---@param x number
---@param agitation number
---@return number
local function RampRise(spec, x, agitation)
    return ForceCurve.Evaluate(spec, x, 0.5, agitation, 0) - spec.intentLow
end

---@return integer
function Tests.Run()
    local count = 0
    ---@param condition boolean
    ---@param description string
    local function Check(condition, description)
        assert(condition, "[曲线验证失败] " .. description)
        count = count + 1
    end

    local spec = Fixture()
    local low, sweetHalf, steepness = ForceCurve.Evaluate(spec, 0.5, 0.5, 0, 0)
    Check(Near(low, spec.intentLow), "甜蜜区中心是最低力度")
    Check(Near(sweetHalf, spec.sweetHalfMax) and Near(steepness, spec.steepBase),
        "无状态时甜蜜区与陡峭度取基准值")
    Check(Near(spec.sweetHalfMax * 2, 0.10), "全宽基准是 10%")
    Check(Near(spec.sweetHalfMin * 2, 0.04), "全宽下限是 4%")
    local left = ForceCurve.Evaluate(spec, 0, 0.5, 0, 0)
    local right = ForceCurve.Evaluate(spec, 1, 0.5, 0, 0)
    Check(Near(left, spec.intentHigh) and Near(right, left), "两端力度相等且为本状态最高")
    Check(left > low, "两端比中间大")
    Check(left <= spec.forceMax and low >= spec.forceMin, "力度落在 80～1612 N 内")
    local insideFlat = ForceCurve.Evaluate(spec, 0.5 + sweetHalf - 0.001, 0.5, 0, 0)
    Check(Near(insideFlat, spec.intentLow), "甜蜜区内力度不变")
    local outsideFlat = ForceCurve.Evaluate(spec, 0.5 + sweetHalf + 0.001, 0.5, 0, 0)
    Check(outsideFlat > spec.intentLow, "甜蜜区外力度开始上升")
    Check(ForceCurve.Evaluate(spec, -1, 0.5, 0, 0) == left
        and ForceCurve.Evaluate(spec, 2, 0.5, 0, 0) == left, "条外位置钳制到端点")

    -- 连续渐变：离开甜蜜区一点不会直接跳到最大值。
    local justOutside = ForceCurve.Evaluate(spec, 0.5 + sweetHalf + 0.002, 0.5, 0, 0)
    Check(justOutside > spec.intentLow and justOutside < left, "区外一点是渐变，不是陡跳")
    local midRise = ForceCurve.Evaluate(spec, 0.75, 0.5, 0, 0)
    Check(midRise > spec.intentLow and midRise < left, "半程处介于甜蜜区与端点之间")

    -- 仅暴躁收窄；疲劳不动宽度。
    local _, halfHot = ForceCurve.Evaluate(spec, 0.5, 0.5, 1, 0)
    Check(halfHot < sweetHalf, "暴躁收窄甜蜜区")
    Check(Near(halfHot, spec.sweetHalfMax * (1 - spec.sweetNarrowAgitation)), "暴躁收窄按确认比例")
    Check(halfHot >= spec.sweetHalfMin, "收窄不越过全宽 4% 下限")
    local _, halfFatigued = ForceCurve.Evaluate(spec, 0.5, 0.5, 0, 1)
    Check(Near(halfFatigued, sweetHalf), "疲劳不收窄也不放宽甜蜜区")
    local _, _, steepHot = ForceCurve.Evaluate(spec, 0.5, 0.5, 1, 0)
    Check(steepHot > steepness, "暴躁提高陡峭度")
    local calmRise = RampRise(spec, 0.75, 0)
    local hotRise = RampRise(spec, 0.75, 1)
    Check(hotRise > calmRise, "暴躁让曲线更快升到端点，也就是更陡")

    -- 疲劳减力：只减弱可用力量，不抬高最低段。
    local fatiguedLow = ForceCurve.Evaluate(spec, 0.5, 0.5, 0, 1)
    Check(fatiguedLow < low, "疲劳把最低力度也减弱，不上移")
    -- 120 × 0.65 = 78 N 低于 80 N 下限，按确认口径截断到下限。
    Check(Near(spec.intentLow * (1 - spec.fatigueForceCut), 78), "疲劳减力按确认比例")
    Check(Near(fatiguedLow, spec.forceMin), "疲劳减力结果截断到 80 N 下限")
    local fatigueAboveFloor = Fixture()
    fatigueAboveFloor.intentLow = 400
    local aboveFloor = ForceCurve.Evaluate(fatigueAboveFloor, 0.5, 0.5, 0, 1)
    Check(Near(aboveFloor, 400 * (1 - fatigueAboveFloor.fatigueForceCut)),
        "未触及下限时疲劳减力按比例生效")
    local fatiguedTop = ForceCurve.Evaluate(spec, 0, 0.5, 0, 1)
    Check(fatiguedTop < left, "疲劳也减弱两端最高力度")
    Check(fatiguedTop >= spec.forceMin, "疲劳减力不越过力度下限")
    Check(Near(ForceCurve.FatiguedForce(spec, 10, 1), spec.forceMin), "低于下限的力度截断到 80 N")
    Check(Near(ForceCurve.FatiguedForce(spec, 99999, 0), spec.forceMax), "超过上限的力度截断到 1612 N")
    -- 意图力度不受疲劳影响，档案要区分"想踩多重"和"实际踩多重"。
    Check(Near(ForceCurve.IntentForce(spec, 0, 0.5, 0), spec.intentHigh), "意图力度保留未衰减的最高值")

    -- 漂移：幅度由疲劳与暴躁共同决定，方向由种子决定，上限 ±18 个百分点。
    local calm = ForceCurve.Create(Fixture(), 11)
    Check(Near(calm.sweetCenter, spec.sweetBase), "零状态不漂移，中心就是基准")
    local agitated = ForceCurve.Create(Fixture(), 11)
    assert(agitated:Lock("test") ~= nil, "漂移测试需要先按停")
    Check(agitated:SetState(1, 0), "按停后可设置暴躁")
    Check(agitated:Resume(), "设置状态后可重开本轮")
    Check(math.abs(agitated.sweetCenter - spec.sweetBase) <= spec.sweetDriftMax + 0.000000001,
        "暴躁驱动的漂移不越过 ±18 个百分点")
    local tired = ForceCurve.Create(Fixture(), 11)
    assert(tired:Lock("test") ~= nil, "漂移测试需要先按停")
    Check(tired:SetState(0, 1), "按停后可设置疲劳")
    Check(tired:Resume(), "设置状态后可重开本轮")
    Check(math.abs(tired.sweetCenter - spec.sweetBase) > 0, "疲劳单独也参与漂移")
    Check(math.abs(tired.sweetCenter - spec.sweetBase) <= spec.sweetDriftMax * spec.fatigueDriftWeight
        + 0.000000001, "疲劳漂移幅度按权重受限")
    Check(math.abs(tired.sweetCenter - spec.sweetBase) < math.abs(agitated.sweetCenter - spec.sweetBase),
        "同权重下疲劳漂移小于拉满暴躁")
    local both = ForceCurve.Create(Fixture(), 11)
    assert(both:Lock("test") ~= nil, "漂移测试需要先按停")
    Check(both:SetState(1, 1), "可同时设置两个状态")
    Check(both:Resume(), "设置状态后可重开本轮")
    Check(math.abs(both.sweetCenter - spec.sweetBase) <= spec.sweetDriftMax + 0.000000001,
        "两个状态合成的漂移仍不超过 ±18 个百分点")

    local model = ForceCurve.Create(Fixture(), 7)
    Check(model.moving and #model.records == 0, "Create 直接开始本轮，不造记录")
    Check(model.seed == 7 and model.agitation == 0 and model.fatigue == 0, "初始状态为零，不预设隐藏状态")
    Check(Near(model.speed, model.spec.cursorSpeed), "无状态时扫速为基础值")
    local firstCenter = model.sweetCenter
    Check(math.abs(firstCenter - 0.5) <= 0.18, "中心漂移在确认半径内")
    model:Update(0)
    Check(model.elapsed == 0 and Near(model.x, 0), "零 dt 不推进")
    model:Update(0.25)
    Check(Near(model.x, 0.6 * 0.25), "游标按基础扫速前进")
    Check(Near(model.force, ForceCurve.Evaluate(model.spec, model.x, model.sweetCenter, 0, 0)),
        "游标力度与曲线求值一致")
    Check(Near(model.intentForce, ForceCurve.IntentForce(model.spec, model.x, model.sweetCenter, 0)),
        "游标意图力度与曲线求值一致")

    local big, small = ForceCurve.Create(Fixture(), 21), ForceCurve.Create(Fixture(), 21)
    big:Update(4)
    for _ = 1, 240 do small:Update(1 / 60) end
    Check(Near(big.x, small.x) and Near(big.force, small.force), "同种子跨帧率结果一致")
    Check(big.randomState_ == small.randomState_, "跨帧率消耗相同随机流")
    -- 漂移幅度完全由状态决定：零状态无论种子如何都不漂移。
    local otherSeed = ForceCurve.Create(Fixture(), 22)
    Check(Near(otherSeed.sweetCenter, firstCenter), "零状态下种子不改变中心，漂移幅度为零")

    local paused, continuous = ForceCurve.Create(Fixture(), 5), ForceCurve.Create(Fixture(), 5)
    paused:Update(0.1)
    local pausedX, pausedElapsed = paused.x, paused.elapsed
    -- 暂停靠不调用 Update；暂停期间仅读取求值，不能推进模型。
    for _ = 1, 20 do ForceCurve.Evaluate(paused.spec, paused.x, paused.sweetCenter, 0, 0) end
    Check(paused.x == pausedX and paused.elapsed == pausedElapsed, "只读求值不推进游标")
    paused:Update(0.2)
    continuous:Update(0.3)
    Check(Near(paused.x, continuous.x), "暂停后仅累计有效运动时间")

    local locked = ForceCurve.Create(Fixture(), 9)
    locked:Update(0.2)
    local record = locked:Lock("keyboard")
    assert(record ~= nil, "首次 Lock 应返回记录")
    Check(not locked.moving and #locked.records == 1, "Lock 停止并追加记录")
    Check(record.source == "keyboard" and record.seed == 9 and Near(record.elapsed, 0.2),
        "记录来源/种子/时间真实")
    Check(Near(record.force, ForceCurve.Evaluate(locked.spec, record.x, record.sweetCenter, 0, 0))
        and Near(record.sweetCenter, locked.sweetCenter), "记录力度与中心来自真实求值")
    Check(Near(record.intentForce, ForceCurve.IntentForce(locked.spec, record.x, record.sweetCenter, 0)),
        "记录保留未衰减的意图力度")
    Check(record.sweetHalf > 0 and record.steepness >= locked.spec.steepBase, "记录甜蜜区半宽与陡峭度")
    locked:Update(10)
    Check(locked.x == record.x, "锁定后 Update 不移动")
    Check(locked:Lock("touch") == nil and #locked.records == 1, "重复 Lock 幂等")
    local movingModel = ForceCurve.Create(Fixture(), 9)
    Check(not movingModel:SetState(0.5, 0.5), "运动中不允许改状态")

    Check(locked:SetState(1, 0) and Near(locked.agitation, 1) and locked.fatigue == 0,
        "锁定时可单独设置暴躁")
    Check(locked.speed > locked.spec.cursorSpeed, "暴躁加速游标")
    Check(locked:SetState(0, 1) and Near(locked.fatigue, 1) and Near(locked.agitation, 0),
        "暴躁与疲劳是两个独立变量，可分别设置")
    Check(locked.speed < locked.spec.cursorSpeed, "疲劳减慢游标")
    Check(not pcall(function() locked:SetState(-0.1, 0) end)
        and not pcall(function() locked:SetState(0, 1.2) end)
        and not pcall(function() locked:SetState(0 / 0, 0) end),
        "拒绝越界与 NaN 状态")

    local beforeCenter = locked.sweetCenter
    local phaseBefore = locked.phase_
    Check(locked:Resume() and locked.moving and locked.elapsed == 0, "Resume 开始新一轮")
    Check(locked.sweetCenter ~= beforeCenter, "每轮重新确定中心漂移")
    Check(locked.phase_ == phaseBefore, "新一轮不重置累计相位，游标从当前摆位继续")
    Check(locked.x >= 0 and locked.x <= 1, "新一轮起点仍在条内")
    locked:Update(0.2)
    local second = locked:Lock("touch")
    assert(second ~= nil, "第二轮应能 Lock")
    Check(second.fatigue == 1 and #locked.records == 2, "新记录保留独立状态且历史不丢")
    Check(locked:Start() and #locked.records == 2, "Start 也保留已有历史")
    local snapshot = locked.records[1]
    assert(snapshot ~= nil, "历史记录缺失")
    local savedX, savedForce = snapshot.x, snapshot.force
    second.x, second.force, second.source = -999, -999, "外部修改"
    Check(snapshot.x == savedX and snapshot.force == savedForce, "Lock 返回快照与历史独立")

    -- Create 即开始本轮，改状态必须先按停；这里用 Lock 停在起点再分别设状态后重开。
    local jittered, steady = ForceCurve.Create(Fixture(), 33), ForceCurve.Create(Fixture(), 33)
    assert(jittered:Lock("test") ~= nil and steady:Lock("test") ~= nil, "抖动测试需要先按停")
    Check(jittered:SetState(1, 0) and steady:SetState(0, 0), "按停后可分别设置状态")
    Check(jittered:Resume() and steady:Resume(), "设置状态后可重开本轮")
    ---@type number
    local maxDeviation = 0
    for step = 1, 120 do
        local dt = 1 / 60
        jittered:Update(dt)
        steady:Update(dt)
        maxDeviation = math.max(maxDeviation, math.abs(jittered.x - steady.x))
    end
    Check(maxDeviation > 0.005, "暴躁让游标真的抖动")
    Check(jittered.x >= 0 and jittered.x <= 1, "抖动不会把游标甩出条外")
    local calmModel = ForceCurve.Create(Fixture(), 33)
    Check(calmModel.spec.jitterAmp > 0 and maxDeviation < 0.6,
        "抖动幅度受配置上限约束")

    ---@param change fun(spec: ForceCurveSpec)
    ---@param description string
    local function RejectSpec(change, description)
        local bad = Fixture()
        change(bad)
        assert(not pcall(ForceCurve.Create, bad, 1), "[曲线验证失败] " .. description)
        count = count + 1
    end
    RejectSpec(function(c) c.cursorSpeed = 0 end, "拒绝零扫速")
    RejectSpec(function(c) c.forceMin = 0 end, "拒绝零力度下限")
    RejectSpec(function(c) c.forceMax = 10 end, "拒绝上限低于下限")
    RejectSpec(function(c) c.intentHigh = 10 end, "拒绝最高意图低于最低意图")
    RejectSpec(function(c) c.intentLow = -1 end, "拒绝负最低意图力度")
    RejectSpec(function(c) c.rampWidth = 0 end, "拒绝零抬升宽度")
    RejectSpec(function(c) c.rampWidth = 1.5 end, "拒绝越界抬升宽度")
    RejectSpec(function(c) c.steepBase = 0.5 end, "拒绝小于一的陡峭指数")
    RejectSpec(function(c) c.sweetBase = 0.05 end, "拒绝没有给最宽甜蜜区留余量的中心")
    RejectSpec(function(c) c.sweetBase = 0.95 end, "拒绝右侧没有余量的中心")
    RejectSpec(function(c) c.sweetDriftMax = 0.6 end, "拒绝超过半条的漂移上限")
    RejectSpec(function(c) c.sweetDriftMax = -1 end, "拒绝负漂移上限")
    RejectSpec(function(c) c.agitationDriftWeight = -1 end, "拒绝负暴躁漂移权重")
    RejectSpec(function(c) c.fatigueDriftWeight = -1 end, "拒绝负疲劳漂移权重")
    RejectSpec(function(c) c.sweetHalfMin = 0 end, "拒绝零甜蜜区最小半宽")
    RejectSpec(function(c) c.sweetHalfMax = 0.01 end, "拒绝最大半宽小于最小半宽")
    -- 0.5 - 0.18 = 0.32 是最大漂移后的最小中心，最宽半宽 0.35 会越界。
    RejectSpec(function(c) c.sweetHalfMax = 0.35 end, "拒绝没有给中心留余量的最宽半宽")
    RejectSpec(function(c) c.sweetNarrowAgitation = 1.5 end, "拒绝越界暴躁收窄")
    RejectSpec(function(c) c.fatigueForceCut = 1.5 end, "拒绝越界疲劳减力")
    RejectSpec(function(c) c.jitterAmp = -1 end, "拒绝负抖动幅度")
    RejectSpec(function(c) c.jitterFreq1 = 0 end, "拒绝零抖动频率")
    RejectSpec(function(c) c.speedFatigue = 1 end, "拒绝会把游标停住的疲劳衰减")
    RejectSpec(function(c) c.speedFatigue = 1.4 end, "拒绝越界疲劳衰减")
    Check(not pcall(ForceCurve.Create, Fixture(), -1)
        and not pcall(ForceCurve.Create, Fixture(), 0.5)
        and not pcall(ForceCurve.Create, Fixture(), 4294967296), "拒绝非法 LCG 种子")
    Check(ForceCurve.Create(Fixture(), 0).moving
        and ForceCurve.Create(Fixture(), 4294967295).moving, "支持 LCG 两端合法种子")
    local dtModel = ForceCurve.Create(Fixture(), 1)
    Check(not pcall(function() dtModel:Update(-1) end)
        and not pcall(function() dtModel:Update(0 / 0) end), "拒绝负 dt 与 NaN dt")

    local copied = ForceCurve.Create(Fixture(), 3)
    local external = Fixture()
    local externalModel = ForceCurve.Create(external, 3)
    external.cursorSpeed, external.sweetHalfMax = 99, 0.4
    Check(copied.spec.cursorSpeed == 0.6 and externalModel.spec.cursorSpeed == 0.6,
        "构造深拷贝配置，外部修改不影响模型")

    print("[曲线验证] PASS，纯 Lua 形状/减力/漂移/抖动/状态断言数=" .. count)
    return count
end

return Tests
