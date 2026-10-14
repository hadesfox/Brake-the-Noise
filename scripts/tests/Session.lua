-- 会话流程纯逻辑验证：机会上限、发帖门槛、换车约束、后果策略留空。
local SessionFlow = require("core.Session")
local FlowConfig = require("config.Flow")

local Tests = {}

function Tests.Run()
    local count = 0
    local function check(condition, description)
        assert(condition, "[会话验证失败] " .. description)
        count = count + 1
    end

    local session = SessionFlow.Create(FlowConfig, 20261014)
    check(session:TestsUsed() == 0, "开局未使用机会")
    check(session:TestsRemaining() == 3, "开局剩余三次机会")
    check(session:PostingState() == SessionFlow.POST_BLOCKED, "未测试前不能发帖")
    check(session:CanChangeVehicle() == false, "没有历史时不能换车")
    check(session:VehicleIndex() == 1, "开局是第一台车")
    local weather = session:Weather()
    check(type(weather.id) == "string" and weather.id ~= "", "开局确定天气")
    check(session.weatherId == weather.id, "天气在会话内一致")

    -- 落点后果：刹车永远走计次路径；踩空/踩油门在作者定案前保持留空。
    check(session:ResolveOutcome("brake") == SessionFlow.POLICY_CONSUME, "刹车结果计次")
    check(session:ResolveOutcome("missed") == SessionFlow.POLICY_UNSET, "踩空策略留空")
    check(session:ResolveOutcome("throttle") == SessionFlow.POLICY_UNSET, "踩油门策略留空")
    check(not pcall(SessionFlow.ResolveOutcome, session, "unknown"), "未知落点结果被拒绝")
    check(not pcall(SessionFlow.RecordTest, session, { outcome = "missed",
        shoeId = "demo-flat", breakState = SessionFlow.BREAK_NONE }),
        "后果留空时不能把踩空记入会话")

    -- 三次正常测试：第一次后可选发帖，第三次后必须发帖。
    for i = 1, 3 do
        local entry = session:RecordTest({ outcome = "brake", shoeId = "demo-flat",
            force = 800 + i, breakState = SessionFlow.BREAK_NONE, source = "test" })
        check(entry.testIndex == i, "第 " .. i .. " 次测试序号正确")
        check(entry.sequence == i, "第 " .. i .. " 次尝试序号正确")
        check(entry.vehicleIndex == 1, "第 " .. i .. " 次记录当前车辆")
        check(entry.weatherId == session.weatherId, "第 " .. i .. " 次记录当前天气")
        check(entry.counted == true, "第 " .. i .. " 次占用机会")
        if i == 1 then check(session:PostingState() == SessionFlow.POST_OPTIONAL, "第一次后可提前发帖") end
        if i == 2 then check(session:PostingState() == SessionFlow.POST_OPTIONAL, "第二次后仍可发帖") end
        if i == 3 then check(session:PostingState() == SessionFlow.POST_REQUIRED, "第三次后必须发帖") end
    end
    check(session:TestsUsed() == 3, "用满三次机会")
    check(session:TestsRemaining() == 0, "没有剩余机会")
    check(session:CanTest() == false, "用满后不能再测试")
    check(not pcall(SessionFlow.RecordTest, session, { outcome = "brake",
        shoeId = "demo-flat", breakState = SessionFlow.BREAK_NONE }),
        "超过三次被拒绝")
    check(session:CanChangeVehicle() == false, "正常结果不能换车")

    -- 换车：只有断裂后可用，且不重置次数与历史。
    local session2 = SessionFlow.Create(FlowConfig, 7)
    session2:RecordTest({ outcome = "brake", shoeId = "demo-slim",
        breakState = SessionFlow.BREAK_DEFORMED, source = "test" })
    check(session2:CanChangeVehicle() == false, "变形不能换车")
    session2:RecordTest({ outcome = "brake", shoeId = "demo-slim",
        breakState = SessionFlow.BREAK_ROOT, source = "test" })
    check(session2:CanChangeVehicle() == true, "根部断裂可以换车")
    local before = session2:TestsUsed()
    check(session2:ChangeVehicle() == true, "换车成功")
    check(session2:VehicleIndex() == 2, "车辆序号递增")
    check(session2:TestsUsed() == before, "换车不重置总次数")
    check(#session2.tests == 2, "换车不抹掉历史")
    session2:RecordTest({ outcome = "brake", shoeId = "demo-slim",
        breakState = SessionFlow.BREAK_ROD, source = "test" })
    check(session2:CanChangeVehicle() == true, "连杆断裂也可以换车")
    check(session2:ChangeVehicle() == true, "第二次换车成功")
    check(session2:VehicleIndex() == 3, "第三次车辆")

    -- 快照是只读副本，外部修改不影响会话。
    local snapshot = session:Snapshot()
    check(snapshot.testsUsed == 3, "快照记录已用次数")
    check(snapshot.maxTests == 3, "快照记录总次数")
    check(snapshot.postingState == SessionFlow.POST_REQUIRED, "快照记录发帖门槛")
    check(#snapshot.tests == 3, "快照包含全部测试")
    local firstTest = assert(snapshot.tests[1], "快照缺少第一条测试")
    firstTest.force = -1
    local storedFirst = assert(session.tests[1], "会话缺少第一条测试")
    check(storedFirst.force ~= -1, "修改快照不改写会话历史")

    -- 发帖标记：用满后必须发帖，且不能绕过门槛。
    local session3 = SessionFlow.Create(FlowConfig, 11)
    check(session3:MarkPosted() == false, "未测试不能发帖")
    check(session3:HasPosted() == false, "未发帖状态正确")
    session3:RecordTest({ outcome = "brake", shoeId = "demo-flat", breakState = SessionFlow.BREAK_NONE })
    check(session3:MarkPosted() == true, "第一次测试后可提前发帖")
    check(session3:HasPosted() == true, "发帖状态被记录")

    -- 不同种子给出可复现且不越界的天气。
    local same1 = SessionFlow.Create(FlowConfig, 99)
    local same2 = SessionFlow.Create(FlowConfig, 99)
    check(same1.weatherId == same2.weatherId, "同种子天气可复现")
    check(same1:WeatherById(same1.weatherId) ~= nil, "天气可按 id 查回")
    check(same1:WeatherById("no-such-weather") == nil, "未知天气返回空")

    -- 已确认规则不可被配置改写：总次数必须为 3。
    local badFlow = { version = "x", maxTests = 4,
        outcomePolicy = { missed = "unset", throttle = "unset" },
        character = FlowConfig.character, weather = FlowConfig.weather }
    check(not pcall(SessionFlow.Create, badFlow, 1), "总次数不是 3 时被拒绝")
    local badPolicy = { version = "x", maxTests = 3,
        outcomePolicy = { missed = "guess", throttle = "unset" },
        character = FlowConfig.character, weather = FlowConfig.weather }
    check(not pcall(SessionFlow.Create, badPolicy, 1), "未知后果策略被拒绝")
    local noWeather = { version = "x", maxTests = 3,
        outcomePolicy = { missed = "unset", throttle = "unset" },
        character = FlowConfig.character, weather = {} }
    check(not pcall(SessionFlow.Create, noWeather, 1), "没有天气时被拒绝")

    -- 后果策略已确认时，留空分支之外的两条路径都要能走通。
    local consumeFlow = { version = "x", maxTests = 3,
        outcomePolicy = { missed = "consume", throttle = "consume" },
        character = FlowConfig.character, weather = FlowConfig.weather }
    local consumeSession = SessionFlow.Create(consumeFlow, 3)
    check(consumeSession:ResolveOutcome("missed") == SessionFlow.POLICY_CONSUME, "踩空可配置为计次")
    consumeSession:RecordTest({ outcome = "missed", shoeId = "demo-flat",
        breakState = SessionFlow.BREAK_NONE })
    check(consumeSession:TestsUsed() == 1, "踩空计次时占用机会")
    local retryFlow = { version = "x", maxTests = 3,
        outcomePolicy = { missed = "retry", throttle = "retry" },
        character = FlowConfig.character, weather = FlowConfig.weather }
    local retrySession = SessionFlow.Create(retryFlow, 3)
    retrySession:RecordTest({ outcome = "missed", shoeId = "demo-flat",
        breakState = SessionFlow.BREAK_NONE })
    check(retrySession:TestsUsed() == 0, "踩空重试时不占用机会")
    check(#retrySession.tests == 1, "重试仍保留历史记录")
    local retryEntry = assert(retrySession.tests[1], "重试缺少历史记录")
    check(retryEntry.testIndex == nil, "未计次记录没有测试序号")

    print("[会话验证] PASS，断言数=" .. count)
    return count
end

return Tests
