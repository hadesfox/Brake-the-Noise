-- P1.2 纯 Lua 回归：76 项检查，仅使用测试 fixtures，不读取 Demo 或正式游戏配置。
local Landing = require("gameplay.Landing")
local Tests = {}

-- 测试 fixture 保留具体非空数组的推导类型；运行接口仍校验 LandingConfig。
local function Fixture()
    ---@type LandingBounds
    local bounds = { minX = 0, maxX = 1, minY = 0, maxY = 1 }
    return {
        speed = 0.5,
        bounds = bounds,
        habitWeight = 0.25,
        pedal = { x = 0.25, y = 0.25, w = 0.5, h = 0.5 },
        shoes = {
            { id = "square", name = "测试方鞋", parts = { { x = -0.25, y = -0.25, w = 0.5, h = 0.5 } } },
            { id = "split", name = "测试分块鞋", parts = {
                { x = -0.25, y = -0.25, w = 0.125, h = 0.5 },
                { x = 0.125, y = -0.25, w = 0.125, h = 0.5 },
            } },
        },
    }
end

---@param a number
---@param b number
---@return boolean
local function Near(a, b)
    return math.abs(a - b) <= 0.000000001
end

---@param model LandingModel
---@return boolean
local function InBounds(model)
    local bounds = model.config.bounds
    return model.x >= bounds.minX and model.x <= bounds.maxX
        and model.y >= bounds.minY and model.y <= bounds.maxY
end

---@param a LandingRecord
---@param b LandingRecord
---@return boolean
local function SameRecord(a, b)
    return a.x == b.x and a.y == b.y and a.shoeId == b.shoeId
        and a.area == b.area and a.shoeArea == b.shoeArea and a.pedalArea == b.pedalArea
        and a.shoeCoverage == b.shoeCoverage and a.pedalCoverage == b.pedalCoverage
        and a.hasContact == b.hasContact and a.centroidX == b.centroidX and a.centroidY == b.centroidY
        and a.shoeCentroidX == b.shoeCentroidX and a.shoeCentroidY == b.shoeCentroidY
        and a.throttleArea == b.throttleArea and a.hasThrottleContact == b.hasThrottleContact
        and a.outcome == b.outcome
        and a.elapsed == b.elapsed and a.seed == b.seed and a.source == b.source
end

-- 油门放在刹车踏板右侧、贴近移动范围边缘；形状更窄更长，贴合现实摆放。
-- 位置与测试 Fixture 的踏板（x 0.25～0.75）分离，不能重叠。
---@return LandingRect
local function ThrottleFixture()
    return { x = 0.78, y = 0.30, w = 0.06, h = 0.40 }
end

---@return integer
function Tests.Run()
    local count = 0
    ---@param condition boolean
    ---@param description string
    local function Check(condition, description)
        assert(condition, "[落点验证失败] " .. description)
        count = count + 1
    end

    local config = Fixture()
    local pedal, shoe = config.pedal, config.shoes[1]
    local full = Landing.Contact(pedal, shoe, 0.5, 0.5)
    Check(Near(full.area, 0.25), "完全重叠的真实面积")
    Check(Near(full.shoeArea, 0.25) and Near(full.pedalArea, 0.25), "鞋底和踏板面积")
    Check(full.shoeCoverage == 1 and full.pedalCoverage == 1, "完全重叠的双覆盖率")
    Check(#full.intersections == 1 and full.intersections[1].x == 0.25
        and full.intersections[1].y == 0.25 and full.intersections[1].w == 0.5
        and full.intersections[1].h == 0.5, "交集使用绝对场景矩形")
    local half = Landing.Contact(pedal, shoe, 0.75, 0.5)
    Check(Near(half.area, 0.125), "水平半重叠")
    Check(Near(half.shoeCoverage, 0.5) and Near(half.pedalCoverage, 0.5), "半重叠的双覆盖率")
    assert(half.intersections[1] ~= nil, "半重叠必须返回交集")
    Check(half.intersections[1].x == 0.5 and half.intersections[1].w == 0.25, "半重叠交集位置和宽度")
    local vertical = Landing.Contact(pedal, shoe, 0.5, 0.75)
    Check(Near(vertical.area, 0.125), "垂直半重叠")
    local edge = Landing.Contact(pedal, shoe, 1, 0.5)
    Check(edge.area == 0 and #edge.intersections == 0, "只共边没有接触")
    Check(edge.shoeCoverage == 0 and edge.pedalCoverage == 0, "共边覆盖率为零")
    local corner = Landing.Contact(pedal, shoe, 1, 1)
    Check(corner.area == 0 and #corner.intersections == 0, "只共角没有接触")
    local none = Landing.Contact(pedal, shoe, 1.25, 0.5)
    Check(none.area == 0 and none.shoeCoverage == 0 and none.pedalCoverage == 0, "完全无接触")
    local split = Landing.Contact(pedal, config.shoes[2], 0.5, 0.5)
    Check(Near(split.area, 0.125) and Near(split.shoeArea, 0.125), "逐块计算鞋形，不用包围盒")
    Check(split.shoeCoverage == 1 and Near(split.pedalCoverage, 0.5), "缺口鞋双覆盖率分母不同")
    Check(#split.intersections == 2, "鞋形返回两个真实交集")
    local gap = Landing.Contact({ x = 0.4, y = 0.25, w = 0.2, h = 0.5 }, config.shoes[2], 0.5, 0.5)
    Check(gap.area == 0, "踏板位于鞋底缺口时不误算包围盒")
    local common = Fixture()
    common.shoes[1].parts = {
        { x = -0.25, y = -0.25, w = 0.25, h = 0.5 },
        { x = 0, y = -0.25, w = 0.25, h = 0.5 },
    }
    local joined = Landing.Contact(common.pedal, common.shoes[1], 0.5, 0.5)
    Check(Near(joined.area, 0.25) and #joined.intersections == 2, "鞋矩形共边合法且不重复面积")
    Check(Landing.Create(common, 1).moving, "Create 允许共边鞋形")
    local degenerate = Landing.Contact({ x = 0.25, y = 0.25, w = 0, h = 0.5 }, shoe, 0.5, 0.5)
    Check(degenerate.area == 0 and degenerate.pedalCoverage == 0, "零踏板面积安全归一化")
    local emptyShoe = { id = "empty", name = "退化几何", parts = {} } --[[@as LandingShoe]]
    local empty = Landing.Contact(pedal, emptyShoe, 0.5, 0.5)
    Check(empty.area == 0 and empty.shoeArea == 0 and empty.shoeCoverage == 0, "空鞋底安全归一化")
    local zeroShoe = { id = "zero", name = "退化鞋块", parts = { { x = 0, y = 0, w = 0, h = 0 } } }
    local zero = Landing.Contact(pedal, zeroShoe, 0.5, 0.5)
    Check(zero.area == 0 and zero.shoeCoverage == 0 and #zero.intersections == 0, "零尺寸鞋块安全")
    local tiny = Landing.Contact(pedal, shoe, 1 - 0.00000001, 0.5)
    Check(tiny.area > 0 and tiny.shoeCoverage > 0, "真正微小重叠不按擦边吞掉")

    -- 受力重心：真实交集面积重心，与鞋中心分开；零接触不给重心，也不除以零。
    Check(full.hasContact and Near(assert(full.centroidX), 0.5) and Near(assert(full.centroidY), 0.5),
        "完全重叠的受力重心在交集中心")
    Check(Near(assert(half.centroidX), 0.625) and Near(assert(half.centroidY), 0.5),
        "半重叠的受力重心落在真实交集里，不是鞋中心")
    Check(assert(half.centroidX) ~= 0.75, "受力重心与鞋中心 0.75 分开记录")
    Check(not edge.hasContact and edge.centroidX == nil and edge.centroidY == nil,
        "共边零接触没有受力重心")
    Check(not corner.hasContact and corner.centroidX == nil, "共角零接触没有受力重心")
    Check(not none.hasContact and none.centroidX == nil and none.centroidY == nil,
        "完全无接触没有受力重心")
    Check(not degenerate.hasContact and degenerate.centroidX == nil, "零踏板面积不给受力重心")
    Check(not empty.hasContact and empty.centroidX == nil, "空鞋底不给受力重心")
    Check(not zero.hasContact and zero.centroidX == nil, "零尺寸鞋块不给受力重心")
    -- 分块鞋：重心按各交集块面积加权，缺口不参与。
    Check(split.hasContact and #split.intersections == 2, "分块鞋有两块交集")
    Check(Near(assert(split.centroidX), 0.5) and Near(assert(split.centroidY), 0.5),
        "分块鞋重心按面积加权")
    local lopsided = Landing.Contact(pedal, shoe, 0.5 - 0.1, 0.5)
    Check(lopsided.hasContact and (lopsided.centroidX or 1) < 0.5,
        "偏心落点把受力重心拉向真实交集一侧")
    Check(full.shoeCentroidX ~= nil and Near(full.shoeCentroidX, 0.5)
        and full.shoeCentroidY ~= nil and Near(full.shoeCentroidY, 0.5),
        "鞋底几何中心与落点一致")
    local splitCentroid = Landing.Contact(pedal, config.shoes[2], 0.5, 0.5)
    Check(Near(assert(splitCentroid.shoeCentroidX), 0.5) and Near(assert(splitCentroid.shoeCentroidY), 0.5),
        "分块鞋鞋底中心按真实鞋块加权，不含缺口")

    local large, small = Landing.Create(Fixture(), 42), Landing.Create(Fixture(), 42)
    Check(large.moving and large.shoeIndex == 1 and large.elapsed == 0 and #large.records == 0,
        "Create 初始化运动，不创建假记录")
    Check(large.x == 0.5 and large.y == 0.5 and large.seed == 42, "中心初始化与初始种子")
    local randomState = small.randomState_
    small:Update(0)
    Check(small.randomState_ == randomState and small.elapsed == 0, "零 dt 不推进随机流")
    Check(not small:Start() and not small:Resume() and small.randomState_ == randomState,
        "已运动时 Start/Resume 无副作用")
    local segmentDt = large.segmentDuration_ / 4
    local initialX, initialY = large.x, large.y
    large:Update(segmentDt)
    local travelled = math.sqrt((large.x - initialX) ^ 2 + (large.y - initialY) ^ 2)
    Check(Near(travelled, large.config.speed * segmentDt), "速度为二维欧氏距离/秒")
    Check(large.randomState_ == randomState, "段内 Update 不逐帧生成随机数")
    large, small = Landing.Create(Fixture(), 42), Landing.Create(Fixture(), 42)
    large:Update(64)
    for _ = 1, 4096 do small:Update(1 / 64) end
    Check(Near(large.x, small.x) and Near(large.y, small.y), "同种子跨大量线段、大/小 dt 同落点")
    Check(large.randomState_ == small.randomState_ and large.targetX == small.targetX
        and large.targetY == small.targetY, "跨 dt 消耗相同随机流并保持相同目标")
    Check(large.elapsed == small.elapsed and InBounds(large), "累计时间相同，大步长不越界")
    local sixty, thirty = Landing.Create(Fixture(), 77), Landing.Create(Fixture(), 77)
    for _ = 1, 360 do sixty:Update(1 / 60) end
    for _ = 1, 180 do thirty:Update(1 / 30) end
    Check(Near(sixty.x, thirty.x) and Near(sixty.y, thirty.y)
        and sixty.randomState_ == thirty.randomState_, "非二进制帧间隔仍保持同种子落点")
    local different = Landing.Create(Fixture(), 43)
    different:Update(64)
    Check(not Near(large.x, different.x) or not Near(large.y, different.y), "不同种子产生不同落点")
    local paused, continuous = Landing.Create(Fixture(), 11), Landing.Create(Fixture(), 11)
    paused:Update(0.125)
    local pauseX, pauseY, pauseElapsed, pauseRandom = paused.x, paused.y, paused.elapsed, paused.randomState_
    -- 失焦/暂停期间 UI 不调用 Update；读取 Contact 也不能推进模型。
    local pauseShoe = paused.config.shoes[1]
    assert(pauseShoe ~= nil, "暂停测试鞋配置缺失")
    for _ = 1, 20 do Landing.Contact(paused.config.pedal, pauseShoe, paused.x, paused.y) end
    Check(paused.x == pauseX and paused.y == pauseY and paused.elapsed == pauseElapsed
        and paused.randomState_ == pauseRandom, "暂停靠不 Update，几何查询无副作用")
    paused:Update(0.25)
    continuous:Update(0.375)
    Check(Near(paused.x, continuous.x) and Near(paused.y, continuous.y), "暂停后仅累计有效运动时间")

    local moving = Landing.Create(Fixture(), 3)
    Check(not moving:SelectShoe(2) and moving.shoeIndex == 1, "运动中禁止换鞋")
    moving:Update(0.5)
    local movingShoe = moving.config.shoes[1]
    assert(movingShoe ~= nil, "记录测试鞋配置缺失")
    local expected = Landing.Contact(moving.config.pedal, movingShoe, moving.x, moving.y)
    local record = moving:Lock("keyboard")
    assert(record ~= nil, "首次 Lock 应返回记录")
    Check(not moving.moving and #moving.records == 1, "Lock 停止运动并追加记录")
    Check(record.x == moving.x and record.y == moving.y and record.elapsed == 0.5
        and record.seed == 3 and record.shoeId == "square" and record.source == "keyboard", "记录中心/鞋/时间/种子/来源真实")
    Check(record.area == expected.area and record.shoeArea == expected.shoeArea
        and record.pedalArea == expected.pedalArea and record.shoeCoverage == expected.shoeCoverage
        and record.pedalCoverage == expected.pedalCoverage, "记录所有几何数据真实计算")
    Check(record.hasContact == expected.hasContact and record.centroidX == expected.centroidX
        and record.centroidY == expected.centroidY and record.shoeCentroidX == expected.shoeCentroidX
        and record.shoeCentroidY == expected.shoeCentroidY, "记录受力重心与鞋中心真实计算")
    Check(moving.previousX == record.x and moving.previousY == record.y, "Lock 保存上次落点")
    moving:Update(100)
    Check(moving.x == record.x and moving.y == record.y and moving.elapsed == record.elapsed,
        "锁定后 Update 不修改中心与时间")
    Check(moving:Lock("touch") == nil and #moving.records == 1, "重复 Lock 幂等、不创建第二条记录")
    Check(moving:SelectShoe(2) and moving.shoeIndex == 2, "锁定后允许换鞋")
    Check(not moving:SelectShoe(0) and not moving:SelectShoe(3) and not moving:SelectShoe(1.5)
        and not moving:SelectShoe(0 / 0), "拒绝非法鞋索引")
    assert(moving.records[1] ~= nil, "首次历史记录缺失")
    Check(SameRecord(moving.records[1], record), "换鞋/锁后 Update 不污染已存历史")
    local savedX = moving.records[1].x
    record.x, record.area, record.shoeId = -999, -999, "外部修改"
    Check(moving.records[1].x == savedX and moving.records[1].area == expected.area
        and moving.records[1].shoeId == "square", "Lock 返回快照与历史独立")
    local historySnapshot = moving:Lock("ignored")
    Check(historySnapshot == nil, "已锁定时不同来源仍不重复锁定")
    local history = moving.records[1]
    assert(history ~= nil, "历史快照缺失")
    local historyX, historyY, historyArea, historyElapsed = history.x, history.y, history.area, history.elapsed
    local resumeX, resumeY = moving.x, moving.y
    Check(moving:Resume() and moving.moving and moving.elapsed == 0, "Resume 开始新测量、重置本次 elapsed")
    Check(moving.x == resumeX and moving.y == resumeY and #moving.records == 1, "Resume 从当前中心续测并保留历史")
    moving:Update(0.25)
    local second = moving:Lock("touch")
    assert(second ~= nil, "Resume 后应能 Lock")
    Check(second.shoeId == "split" and second.elapsed == 0.25 and #moving.records == 2,
        "新记录使用所选鞋和本次时间")
    Check(history ~= moving.records[2] and history.x == historyX and history.y == historyY
        and history.area == historyArea and history.elapsed == historyElapsed, "不同测量的历史记录相互独立")
    Check(moving:Start() and #moving.records == 2 and history.x == historyX, "Start 也保留已有历史")
    local external = Fixture()
    local copied = Landing.Create(external, 9)
    external.speed, external.bounds.minX, external.pedal.w = 123, 0.4, 0.01
    external.shoes[1].id, external.shoes[1].parts[1].w = "篡改", 0.01
    local copiedShoe = copied.config.shoes[1]
    assert(copiedShoe ~= nil, "深拷贝鞋配置缺失")
    local copiedPart = copiedShoe.parts[1]
    assert(copiedPart ~= nil, "深拷贝鞋矩形缺失")
    Check(copied.config.speed == 0.5 and copied.config.bounds.minX == 0
        and copied.config.pedal.w == 0.5 and copiedShoe.id == "square"
        and copiedPart.w == 0.5, "构造深拷贝配置，外部修改不影响模型")

    local habitual = Fixture()
    habitual.habitWeight = 1
    local habit = Landing.Create(habitual, 7)
    habit:Update(0.125)
    local habitRecord = habit:Lock("test")
    assert(habitRecord ~= nil, "习惯测试需要初次记录")
    habit:Resume()
    Check(habit.segmentDuration_ > 0 and InBounds(habit), "habitWeight=1 零长度目标有确定性退路")
    local excursionDuration = habit.segmentDuration_
    habit:Update(excursionDuration)
    Check(habit.targetX == habitRecord.x and habit.targetY == habitRecord.y,
        "habitWeight=1 探索后下一目标精确偏好上次落点")
    habit:Update(habit.segmentDuration_)
    Check(Near(habit.x, habitRecord.x) and Near(habit.y, habitRecord.y), "habitWeight=1 确实返回上次落点")
    habit:Update(16)
    Check(InBounds(habit) and habit.moving, "habitWeight=1 多次往返无死循环且不越界")
    local unbiasedConfig, weightedConfig = Fixture(), Fixture()
    unbiasedConfig.habitWeight, weightedConfig.habitWeight = 0, 0.5
    local unbiased, weighted = Landing.Create(unbiasedConfig, 21), Landing.Create(weightedConfig, 21)
    unbiased:Update(0.125)
    weighted:Update(0.125)
    unbiased:Lock("test")
    weighted:Lock("test")
    unbiased:Resume()
    weighted:Resume()
    assert(weighted.previousX ~= nil and weighted.previousY ~= nil)
    Check(Near(weighted.targetX, (unbiased.targetX + weighted.previousX) / 2)
        and Near(weighted.targetY, (unbiased.targetY + weighted.previousY) / 2), "权重按配置向上次落点插值，无隐藏业务参数")

    -- 油门：与刹车共用同一套逐块交集口径，结果三分。
    -- 用贴近真实比例的鞋型；Fixture 的方鞋比整个踏板还大，会同时盖住油门。
    local throttle = ThrottleFixture()
    ---@type LandingShoe
    local realShoe = { id = "real", name = "真实比例鞋", parts = {
        { x = -0.05, y = -0.16, w = 0.10, h = 0.32 },
    } }
    local onBrake = Landing.Contact(pedal, realShoe, 0.5, 0.5, throttle)
    Check(onBrake.outcome == "brake" and onBrake.hasThrottleContact == false
        and onBrake.throttleArea == 0, "踩刹车时结果不是油门")
    -- 鞋底横跨踏板右边缘与油门时，正常刹车优先，油门不会吞掉刹车。
    local straddle = Landing.Contact(pedal, realShoe, 0.78, 0.5, throttle)
    Check(straddle.area > 0 and straddle.throttleArea > 0 and straddle.outcome == "brake",
        "鞋底同时碰到刹车与油门时结果仍是刹车")
    local onThrottle = Landing.Contact(pedal, realShoe, 0.81, 0.5, throttle)
    Check(onThrottle.outcome == "throttle" and onThrottle.hasThrottleContact
        and onThrottle.throttleArea > 0, "踩到油门时结果标记为 throttle")
    Check(onThrottle.area == 0, "踩油门时没有刹车交集，不进入刹车载荷计算")
    local missed = Landing.Contact(pedal, realShoe, 0.5, 0.05, throttle)
    Check(missed.outcome == "missed" and not missed.hasThrottleContact
        and not missed.hasContact, "两边都没踩到时结果为 missed")
    local noThrottle = Landing.Contact(pedal, realShoe, 0.5, 0.5)
    Check(noThrottle.throttleArea == 0 and noThrottle.outcome == "brake",
        "没有配置油门时行为与旧版一致")
    local throttleOnly = Landing.Contact(pedal, realShoe, 0.81, 0.5)
    Check(throttleOnly.outcome == "missed", "没配置油门时踩到油门位置只算踩空")
    -- 鞋底完全滑到油门右侧后不再接触，结果仍是踩空。
    local throttlePast = Landing.Contact(pedal, realShoe, 0.91, 0.5, throttle)
    Check(throttlePast.throttleArea == 0 and throttlePast.outcome == "missed",
        "鞋底滑过油门后不再算踩到")
    -- 界面复用的交集矩形接口与面积口径一致。
    local throttleRects = Landing.OverlapRects(throttle, realShoe, 0.81, 0.5)
    Check(#throttleRects >= 1, "OverlapRects 返回油门交集矩形")
    local throttleRectSum = 0.0
    for _, rect in ipairs(throttleRects) do throttleRectSum = throttleRectSum + rect.w * rect.h end
    Check(Near(throttleRectSum, onThrottle.throttleArea), "OverlapRects 面积与 Contact 口径一致")
    Check(#Landing.OverlapRects(pedal, realShoe, 0.5, 0.05) == 0, "无交集时返回空列表")

    -- 实测踩到油门的概率：在移动范围内均匀取样，比较不同鞋型。
    -- 概率主要由鞋底宽度决定，不是油门面积占比，因此必须用真实几何统计而不是估算。
    -- 返回两个数：占全部落点的比例，以及占"踩空"的比例（后者才是玩家感知到的意外率）。
    ---@param sampling LandingConfig
    ---@param shoeIndex integer
    ---@param steps integer
    ---@return number overallRate
    ---@return number missedRate
    local function ThrottleRate(sampling, shoeIndex, steps)
        local targetShoe = assert(sampling.shoes[shoeIndex], "统计用鞋型缺失")
        local bounds = sampling.bounds
        local hits, missedCount, total = 0, 0, 0
        for ix = 0, steps do
            for iy = 0, steps do
                local x = bounds.minX + (bounds.maxX - bounds.minX) * (ix / steps)
                local y = bounds.minY + (bounds.maxY - bounds.minY) * (iy / steps)
                total = total + 1
                local contact = Landing.Contact(sampling.pedal, targetShoe, x, y, sampling.throttle)
                if contact.outcome == "throttle" then
                    hits = hits + 1
                    missedCount = missedCount + 1
                elseif contact.outcome == "missed" then
                    missedCount = missedCount + 1
                end
            end
        end
        return hits / total, missedCount > 0 and hits / missedCount or 0
    end
    local probabilityConfig = Fixture()
    probabilityConfig.bounds = { minX = 0.08, maxX = 0.92, minY = 0.12, maxY = 0.88 }
    probabilityConfig.pedal = { x = 0.38, y = 0.24, w = 0.24, h = 0.52 }
    probabilityConfig.throttle = ThrottleFixture()
    probabilityConfig.shoes = {
        { id = "wide", name = "宽底", parts = { { x = -0.11, y = -0.18, w = 0.22, h = 0.36 } } },
        { id = "slim", name = "窄底", parts = { { x = -0.05, y = -0.18, w = 0.10, h = 0.36 } } },
    }
    local wideRate, wideMissedRate = ThrottleRate(probabilityConfig, 1, 200)
    local slimRate, slimMissedRate = ThrottleRate(probabilityConfig, 2, 200)
    Check(wideRate > 0 and wideRate < 1, "踩油门是小概率但非必然事件")
    Check(slimRate < wideRate, "窄底鞋踩到油门的概率低于宽底鞋")
    Check(wideMissedRate > wideRate, "踩空条件下的踩油门率高于占全部落点的比例")
    -- 概率主要由鞋底宽度与油门位置共同决定，这里把真实数字打出来供作者决定摆放。
    print(string.format("[落点验证] 油门实测：宽底 占全部 %.2f%% / 占踩空 %.2f%%；窄底 占全部 %.2f%% / 占踩空 %.2f%%",
        wideRate * 100, wideMissedRate * 100, slimRate * 100, slimMissedRate * 100))

    -- 开发 Demo 的实际摆放：贴刹车右侧、贴近移动范围边缘。这里量出真实概率供作者定摆放。
    local demoConfig = Fixture()
    demoConfig.bounds = { minX = 0.08, maxX = 0.92, minY = 0.12, maxY = 0.88 }
    demoConfig.pedal = { x = 0.38, y = 0.24, w = 0.24, h = 0.52 }
    demoConfig.throttle = { x = 0.64, y = 0.30, w = 0.06, h = 0.40 }
    demoConfig.shoes = {
        { id = "flat", name = "宽底", parts = { { x = -0.11, y = -0.18, w = 0.22, h = 0.36 } } },
        { id = "slim", name = "窄底", parts = { { x = -0.05, y = -0.18, w = 0.10, h = 0.36 } } },
    }
    local demoWide, demoWideMissed = ThrottleRate(demoConfig, 1, 200)
    local demoSlim, demoSlimMissed = ThrottleRate(demoConfig, 2, 200)
    print(string.format("[落点验证] Demo 摆放实测：宽底 占全部 %.2f%% / 占踩空 %.2f%%；窄底 占全部 %.2f%% / 占踩空 %.2f%%",
        demoWide * 100, demoWideMissed * 100, demoSlim * 100, demoSlimMissed * 100))
    Check(demoWide > 0 and demoSlim > 0, "Demo 摆放能真的踩到油门")
    -- 稀有度由摆放位置与"刹车优先"共同决定，且关系不是单调的：
    -- 油门贴着刹车时，鞋底横跨两者会被判为刹车，只有完全滑出刹车后仍碰到油门才算意外，因此反而稀有；
    -- 油门离刹车远到鞋底能完全让开时，纯油门区间变宽，概率反而上升。这里把这个非直觉规律固定下来。
    local adjacentWide = ThrottleRate(demoConfig, 1, 200)
    local detached = Fixture()
    detached.bounds = demoConfig.bounds
    detached.pedal = demoConfig.pedal
    detached.throttle = { x = 0.80, y = 0.30, w = 0.06, h = 0.40 }
    detached.shoes = demoConfig.shoes
    local detachedWide = ThrottleRate(detached, 1, 200)
    Check(detachedWide > adjacentWide, "油门远离刹车后鞋底可完全让开，概率反而更高")
    -- 真正压低概率的杠杆是纵向范围：油门越短，鞋底只在少数高度才碰得到。
    local shortThrottle = Fixture()
    shortThrottle.bounds = demoConfig.bounds
    shortThrottle.pedal = demoConfig.pedal
    shortThrottle.throttle = { x = 0.64, y = 0.42, w = 0.06, h = 0.16 }
    shortThrottle.shoes = demoConfig.shoes
    local shortWide = ThrottleRate(shortThrottle, 1, 200)
    Check(shortWide < adjacentWide, "缩短油门纵向范围能真正降低踩到概率")

    -- 油门与刹车重叠会让同一次落点同时命中两者，结果无法二选一，因此必须拒绝。
    local overlapConfig = Fixture()
    overlapConfig.throttle = { x = 0.5, y = 0.3, w = 0.2, h = 0.3 }
    Check(not pcall(Landing.Create, overlapConfig, 1), "拒绝与刹车重叠的油门")
    -- Fixture 的踏板右边缘是 0.75；油门从这里开始即为共边。
    local touching = Fixture()
    touching.throttle = { x = 0.75, y = 0.25, w = 0.06, h = 0.5 }
    Check(pcall(Landing.Create, touching, 1), "油门与刹车共边允许")

    ---@param change fun(config: LandingConfig)
    ---@param description string
    local function RejectConfig(change, description)
        local bad = Fixture()
        change(bad)
        local ok = pcall(Landing.Create, bad, 1)
        Check(not ok, description)
    end
    RejectConfig(function(c) c.speed = 0 end, "拒绝零速度")
    RejectConfig(function(c) c.speed = math.huge end, "拒绝无限速度")
    RejectConfig(function(c) c.habitWeight = -0.1 end, "拒绝负习惯权重")
    RejectConfig(function(c) c.habitWeight = 1.1 end, "拒绝超范围习惯权重")
    RejectConfig(function(c) c.bounds.maxX = c.bounds.minX end, "拒绝零宽度二维边界")
    RejectConfig(function(c) c.bounds.maxY = 2 end, "拒绝未归一化边界")
    RejectConfig(function(c) c.bounds.minY = 0 / 0 end, "拒绝 NaN 边界")
    RejectConfig(function(c) c.pedal.w = -1 end, "拒绝负矩形宽度")
    RejectConfig(function(c) c.pedal.h = 0 end, "Create 拒绝退化踏板")
    RejectConfig(function(c) c.shoes = {} end, "拒绝空鞋列表")
    RejectConfig(function(c)
        local first = c.shoes[1]
        assert(first ~= nil)
        first.parts = {}
    end, "Create 拒绝空鞋 parts")
    RejectConfig(function(c)
        local first = c.shoes[1]
        assert(first ~= nil)
        local part = first.parts[1]
        assert(part ~= nil)
        part.h = 0
    end, "Create 拒绝退化鞋块")
    RejectConfig(function(c)
        local firstShoe, secondShoe = c.shoes[1], c.shoes[2]
        assert(firstShoe ~= nil and secondShoe ~= nil)
        secondShoe.id = firstShoe.id
    end, "拒绝重复鞋 id")
    RejectConfig(function(c)
        local first = c.shoes[1]
        assert(first ~= nil)
        first.parts[2] = { x = -0.125, y = -0.125, w = 0.5, h = 0.5 }
    end, "拒绝鞋矩形内部重叠双算面积")
    local overlapping = Fixture().shoes[1]
    overlapping.parts[2] = { x = -0.125, y = -0.125, w = 0.5, h = 0.5 }
    Check(not pcall(Landing.Contact, pedal, overlapping, 0.5, 0.5), "Contact 本身也拒绝重叠鞋块")
    Check(not pcall(Landing.Create, Fixture(), -1) and not pcall(Landing.Create, Fixture(), 0.5)
        and not pcall(Landing.Create, Fixture(), 4294967296), "拒绝非法 LCG 种子")
    Check(Landing.Create(Fixture(), 0).seed == 0 and Landing.Create(Fixture(), 4294967295).moving,
        "支持 LCG 两端合法种子")
    Check(not pcall(function() copied:Update(-1) end) and not pcall(function() copied:Update(0 / 0) end),
        "拒绝负 dt 与 NaN dt")
    print("[落点验证] PASS，纯 Lua 几何/运动/历史断言数=" .. count)
    return count
end

return Tests
