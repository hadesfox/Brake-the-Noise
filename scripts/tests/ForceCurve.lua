-- P1.3 纯 Lua 回归：心理曲线的形状、低平区、甜蜜点漂移、抖动与独立状态。
-- 只使用测试 fixtures，不读取 Demo 或正式游戏配置。
local ForceCurve = require("gameplay.ForceCurve")
local Tests = {}

---@return ForceCurveSpec
local function Fixture()
    return {
        cursorSpeed = 0.6,
        flatHalfBase = 0.10,
        flatLevel = 0.12,
        peakLift = 0.70,
        rampWidth = 0.34,
        steepBase = 1.6,
        steepAgitation = 2.4,
        flatNarrow = 0.6,
        widenFatigue = 0.4,
        liftFatigue = 0.16,
        sweetBase = 0.5,
        sweetDrift = 0.18,
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

-- 曲线两端与最低点都不随状态变化，变的只是"从低平区升到端点有多快"。
---@param spec ForceCurveSpec
---@param x number
---@param agitation number
---@return number
local function RampRise(spec, x, agitation)
    local force = ForceCurve.Evaluate(spec, x, 0.5, agitation, 0)
    return force - spec.flatLevel
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
    local low, flatHalf, steepness = ForceCurve.Evaluate(spec, 0.5, 0.5, 0, 0)
    Check(Near(low, spec.flatLevel), "甜蜜点是最低点")
    Check(Near(flatHalf, spec.flatHalfBase) and Near(steepness, spec.steepBase),
        "无状态时低平区与陡峭度取基准值")
    local left = ForceCurve.Evaluate(spec, 0, 0.5, 0, 0)
    local right = ForceCurve.Evaluate(spec, 1, 0.5, 0, 0)
    Check(Near(left, spec.flatLevel + spec.peakLift) and Near(right, left), "两端力度相等且为最高")
    Check(left > low, "两端比中间大")
    local insideFlat = ForceCurve.Evaluate(spec, 0.5 + flatHalf - 0.001, 0.5, 0, 0)
    Check(Near(insideFlat, spec.flatLevel), "低平区内力度不变")
    local outsideFlat = ForceCurve.Evaluate(spec, 0.5 + flatHalf + 0.001, 0.5, 0, 0)
    Check(outsideFlat > spec.flatLevel, "低平区外力度开始上升")
    Check(ForceCurve.Evaluate(spec, -1, 0.5, 0, 0) == left
        and ForceCurve.Evaluate(spec, 2, 0.5, 0, 0) == left, "条外位置钳制到端点")

    local _, flatHalfHot = ForceCurve.Evaluate(spec, 0.5, 0.5, 1, 0)
    Check(flatHalfHot < flatHalf, "暴躁收窄低平区")
    local _, _, steepHot = ForceCurve.Evaluate(spec, 0.5, 0.5, 1, 0)
    Check(steepHot > steepness, "暴躁提高陡峭度")
    local calmRise = RampRise(spec, 0.75, 0)
    local hotRise = RampRise(spec, 0.75, 1)
    Check(calmRise > 0 and calmRise < spec.peakLift, "半程处力度介于低平区与端点之间")
    Check(hotRise > calmRise, "暴躁让曲线更快升到端点，也就是更陡")
    local lowFatigued = ForceCurve.Evaluate(spec, 0.5, 0.5, 0, 1)
    Check(Near(lowFatigued, spec.flatLevel + spec.liftFatigue), "疲劳整体上移最低点")
    Check(lowFatigued > low, "疲劳后想轻也轻不了")
    local _, flatHalfFatigued = ForceCurve.Evaluate(spec, 0.5, 0.5, 0, 1)
    Check(flatHalfFatigued > flatHalf, "疲劳放宽低平区")
    local _, bothHalf = ForceCurve.Evaluate(spec, 0.5, 0.5, 1, 1)
    Check(Near(bothHalf, spec.flatHalfBase * (1 - spec.flatNarrow) * (1 + spec.widenFatigue)),
        "暴躁与疲劳对低平区的作用相乘，不合并为单一状态")
    Check(bothHalf < flatHalfFatigued and bothHalf > flatHalfHot, "两个因素可同时生效")

    local tight = Fixture()
    tight.sweetBase = 0.02
    tight.sweetDrift = 0.5
    local _, tightHalf = ForceCurve.Evaluate(tight, 0.02, 0.02, 0, 1)
    Check(tightHalf <= 0.02, "甜蜜点贴近端点时低平区半宽被夹住，不越出条外")

    local model = ForceCurve.Create(Fixture(), 7)
    Check(model.moving and #model.records == 0, "Create 直接开始本轮，不造记录")
    Check(model.seed == 7 and model.agitation == 0 and model.fatigue == 0, "初始状态为零，不预设隐藏状态")
    Check(Near(model.speed, model.spec.cursorSpeed), "无状态时扫速为基础值")
    local firstSpot = model.sweetSpot
    Check(math.abs(firstSpot - 0.5) <= 0.18, "甜蜜点在漂移半径内")
    model:Update(0)
    Check(model.elapsed == 0 and Near(model.x, 0), "零 dt 不推进")
    model:Update(0.25)
    Check(Near(model.x, 0.6 * 0.25), "游标按基础扫速前进")
    Check(Near(model.force, ForceCurve.Evaluate(model.spec, model.x, model.sweetSpot, 0, 0)),
        "游标力度与曲线求值一致")

    local big, small = ForceCurve.Create(Fixture(), 21), ForceCurve.Create(Fixture(), 21)
    big:Update(4)
    for _ = 1, 240 do small:Update(1 / 60) end
    Check(Near(big.x, small.x) and Near(big.force, small.force), "同种子跨帧率结果一致")
    Check(big.randomState_ == small.randomState_, "跨帧率消耗相同随机流")
    local other = ForceCurve.Create(Fixture(), 22)
    Check(other.sweetSpot ~= firstSpot, "不同种子给出不同甜蜜点")

    local paused, continuous = ForceCurve.Create(Fixture(), 5), ForceCurve.Create(Fixture(), 5)
    paused:Update(0.1)
    local pausedX, pausedElapsed = paused.x, paused.elapsed
    -- 暂停靠不调用 Update；暂停期间仅读取求值，不能推进模型。
    for _ = 1, 20 do ForceCurve.Evaluate(paused.spec, paused.x, paused.sweetSpot, 0, 0) end
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
    Check(Near(record.force, ForceCurve.Evaluate(locked.spec, record.x, record.sweetSpot, 0, 0))
        and Near(record.sweetSpot, locked.sweetSpot), "记录力度与甜蜜点来自真实求值")
    Check(record.flatHalf > 0 and record.steepness >= locked.spec.steepBase, "记录低平区与陡峭度")
    locked:Update(10)
    Check(locked.x == record.x, "锁定后 Update 不移动")
    Check(locked:Lock("touch") == nil and #locked.records == 1, "重复 Lock 幂等")
    local movingModel = ForceCurve.Create(Fixture(), 9)
    Check(not movingModel:SetState(0.5, 0.5), "运动中不允许改状态")

    Check(locked:SetState(1, 0) and Near(locked.agitation, 1) and locked.fatigue == 0,
        "锁定时可单独设置暴躁")
    local hotSpeed = locked.speed
    Check(hotSpeed > locked.spec.cursorSpeed, "暴躁加速游标")
    Check(locked:SetState(0, 1) and Near(locked.fatigue, 1) and Near(locked.agitation, 0),
        "暴躁与疲劳是两个独立变量，可分别设置")
    Check(locked.speed < locked.spec.cursorSpeed, "疲劳减慢游标")
    Check(not pcall(function() locked:SetState(-0.1, 0) end)
        and not pcall(function() locked:SetState(0, 1.2) end)
        and not pcall(function() locked:SetState(0 / 0, 0) end),
        "拒绝越界与 NaN 状态")

    local beforeSpot = locked.sweetSpot
    local phaseBefore = locked.phase_
    Check(locked:Resume() and locked.moving and locked.elapsed == 0, "Resume 开始新一轮")
    Check(locked.sweetSpot ~= beforeSpot, "每轮重新漂移甜蜜点")
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
    RejectSpec(function(c) c.flatHalfBase = 0 end, "拒绝零低平区")
    RejectSpec(function(c) c.flatHalfBase = 0.6 end, "拒绝超过半条的低平区")
    RejectSpec(function(c) c.flatLevel = -0.1 end, "拒绝负低平区力度")
    RejectSpec(function(c) c.peakLift = 0 end, "拒绝零端点抬升")
    RejectSpec(function(c) c.flatLevel, c.peakLift = 0.5, 0.6 end, "拒绝超过归一化上限的曲线")
    RejectSpec(function(c) c.steepBase = 0.5 end, "拒绝小于一的陡峭指数")
    RejectSpec(function(c) c.flatNarrow = 1.5 end, "拒绝越界暴躁缩减")
    RejectSpec(function(c) c.liftFatigue = 1 end, "拒绝上移越界")
    RejectSpec(function(c) c.sweetBase = 0.05 end, "拒绝没有给最宽低平区留余量的甜蜜点")
    RejectSpec(function(c) c.sweetDrift = -1 end, "拒绝负漂移半径")
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
    external.cursorSpeed, external.flatHalfBase = 99, 0.4
    Check(copied.spec.cursorSpeed == 0.6 and externalModel.spec.cursorSpeed == 0.6,
        "构造深拷贝配置，外部修改不影响模型")

    print("[曲线验证] PASS，纯 Lua 形状/漂移/抖动/状态断言数=" .. count)
    return count
end

return Tests
