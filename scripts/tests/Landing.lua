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
        and a.elapsed == b.elapsed and a.seed == b.seed and a.source == b.source
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
