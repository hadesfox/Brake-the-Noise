-- 单局会话流程（纯逻辑，不依赖渲染、网络与正式数值）。
--
-- 只负责"最多三次测试、第一次后可提前发帖、第三次必须发帖、换车不重置"这些
-- 已确认的流程规则；不决定载荷、损伤、断裂、传播与结局，也不生成任何美术。
--
-- 落点后果（踩空 / 踩到油门）由实施计划第 4.1 节 B2 明确留空，这里不替作者决定：
-- 策略为 unset 时，会话把控制权交回调用方停在占位页，既不扣次数也不免费重试。
-- 模块局部变量用 SessionFlow，实例类型用 SessionModel：避免与类型名同名导致解析冲突。
-- 该注解必须紧贴 `local SessionFlow = {}`，否则成员方法无法被解析。
---@class SessionModel
---@field flow SessionFlowConfig
---@field seed number
---@field weatherId string
---@field vehicleIndex integer
---@field tests SessionTestEntry[]
---@field testsUsed integer
---@field posted boolean
---@field randomState_ number
local SessionFlow = {}
SessionFlow.__index = SessionFlow

local LCG_MODULUS = 4294967296

-- 落点后果策略。
SessionFlow.POLICY_UNSET = "unset"
SessionFlow.POLICY_CONSUME = "consume"
SessionFlow.POLICY_RETRY = "retry"

-- 发帖门槛状态。
SessionFlow.POST_BLOCKED = "blocked"
SessionFlow.POST_OPTIONAL = "optional"
SessionFlow.POST_REQUIRED = "required"

-- 断裂状态取值来自设计文档（正常 / 变形 / 根部断裂 / 连杆断裂）。
-- 只有"断裂"允许换车；变形不换车。换车不重置总次数、人体状态与历史。
SessionFlow.BREAK_NONE = "normal"
SessionFlow.BREAK_DEFORMED = "deformed"
SessionFlow.BREAK_ROOT = "root_break"
SessionFlow.BREAK_ROD = "rod_break"

---@class SessionTestEntry
---@field sequence integer 本次会话中的第几次尝试，含未计次的尝试
---@field testIndex integer? 计入总次数时的序号；未计次为空
---@field vehicleIndex integer
---@field shoeId string
---@field weatherId string
---@field outcome string brake / throttle / missed
---@field counted boolean 是否占用总测试次数
---@field landingX number?
---@field landingY number?
---@field pedalCoverage number?
---@field shoeCoverage number?
---@field intentForce number?
---@field force number?
---@field breakState string? 保留兼容旧版，新版用 structureState
---@field source string
---@field reactionTime number? 反应时间（秒）
---@field brakingTime number? 100-0制动用时（秒），主成绩
---@field brakingDistance number? 制动距离（米）
---@field actualPedalForce number? 实际制动通道力 F×E传导
---@field completionStatus string? "completed" | "failed_miss" | "failed_broken" | "failed_wall"
---@field failureReason string? 失败原因描述
---@field structureState string? "intact" | "broken"
---@field hiddenDamageBefore number? 测试前隐藏损伤累计
---@field hiddenDamageAfter number? 测试后隐藏损伤累计

---@class SessionWeather
---@field id string
---@field name string
---@field sky RGBAColor

---@class SessionOutfit
---@field id string
---@field name string

---@class SessionCharacter
---@field clothing SessionOutfit[]
---@field trousers SessionOutfit[]

---@class SessionPreDriveConfig
---@field ac table<string, any>
---@field seat table<string, any>

---@class SessionFlowConfig
---@field version string
---@field maxTests integer
---@field outcomePolicy table<string, string>
---@field character SessionCharacter
---@field weather SessionWeather[]
---@field preDrive SessionPreDriveConfig
---@field acceleration AccelerationConfig

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

---@param value any
---@param description string
---@return integer
local function RequireInteger(value, description)
    assert(IsFinite(value) and value == math.floor(value), description .. "必须是整数")
    return math.floor(value)
end

---@param policy string
---@return boolean
local function IsKnownPolicy(policy)
    return policy == SessionFlow.POLICY_UNSET or policy == SessionFlow.POLICY_CONSUME
        or policy == SessionFlow.POLICY_RETRY
end

---@param flow SessionFlowConfig
local function ValidateFlow(flow)
    assert(type(flow) == "table", "流程配置必须是 table")
    assert(type(flow.version) == "string" and flow.version ~= "", "流程配置缺少版本")
    -- 总测试次数是已确认规则，不是可调数值；这里只校验一致性，不改写。
    assert(RequireInteger(flow.maxTests, "总测试次数") == 3, "总测试次数必须是 3 次")
    assert(type(flow.outcomePolicy) == "table", "缺少落点后果策略")
    for _, outcome in ipairs({ "missed", "throttle" }) do
        local policy = flow.outcomePolicy[outcome]
        assert(IsKnownPolicy(policy), "未知的落点后果策略：" .. tostring(policy))
    end
    assert(type(flow.weather) == "table" and #flow.weather > 0, "至少需要一个窗外天气")
    for _, weather in ipairs(flow.weather) do
        assert(type(weather.id) == "string" and weather.id ~= "", "天气缺少 id")
    end
    -- 发车前准备与加速阶段：骨架阶段必须有可用的占位结构，否则页面无法构建。
    assert(type(flow.preDrive) == "table", "缺少发车前准备配置")
    assert(type(flow.preDrive.ac) == "table" and type(flow.preDrive.ac.on) == "boolean",
        "空调占位配置缺少 on")
    assert(type(flow.preDrive.seat) == "table" and type(flow.preDrive.seat.position) == "number",
        "座椅占位配置缺少 position")
    assert(type(flow.acceleration) == "table", "缺少加速阶段配置")
    assert(type(flow.acceleration.durationSeconds) == "number" and flow.acceleration.durationSeconds > 0,
        "加速时长必须是正数")
    assert(type(flow.acceleration.targetSpeed) == "number" and flow.acceleration.targetSpeed > 0,
        "目标时速必须是正数")
end

---@param entry SessionTestEntry
---@return SessionTestEntry
local function CopyEntry(entry)
    return {
        sequence = entry.sequence, testIndex = entry.testIndex,
        vehicleIndex = entry.vehicleIndex, shoeId = entry.shoeId,
        weatherId = entry.weatherId, outcome = entry.outcome, counted = entry.counted,
        landingX = entry.landingX, landingY = entry.landingY,
        pedalCoverage = entry.pedalCoverage, shoeCoverage = entry.shoeCoverage,
        intentForce = entry.intentForce, force = entry.force,
        breakState = entry.breakState, source = entry.source,
        reactionTime = entry.reactionTime, brakingTime = entry.brakingTime,
        brakingDistance = entry.brakingDistance, actualPedalForce = entry.actualPedalForce,
        completionStatus = entry.completionStatus, failureReason = entry.failureReason,
        structureState = entry.structureState,
        hiddenDamageBefore = entry.hiddenDamageBefore, hiddenDamageAfter = entry.hiddenDamageAfter,
    }
end

---@class SessionTestInput
---@field outcome string brake / throttle / missed
---@field shoeId string
---@field landingX number?
---@field landingY number?
---@field pedalCoverage number?
---@field shoeCoverage number?
---@field intentForce number?
---@field force number?
---@field breakState string? 保留兼容旧版
---@field source string?
---@field reactionTime number? 反应时间（秒）
---@field brakingTime number? 100-0制动用时（秒）
---@field brakingDistance number? 制动距离（米）
---@field actualPedalForce number? 实际制动通道力
---@field completionStatus string? 完成状态
---@field failureReason string? 失败原因
---@field structureState string? 二态结构状态
---@field hiddenDamageBefore number? 测试前隐藏损伤
---@field hiddenDamageAfter number? 测试后隐藏损伤

---@param flow SessionFlowConfig
---@param seed number
---@return SessionModel
function SessionFlow.Create(flow, seed)
    ValidateFlow(flow)
    assert(IsFinite(seed) and seed == math.floor(seed) and seed >= 0 and seed < LCG_MODULUS,
        "种子必须是 [0,2^32) 的整数")
    local session = setmetatable({}, SessionFlow)
    session.flow = flow
    session.seed = seed
    session.randomState_ = seed
    session.vehicleIndex = 1
    session.tests = {}
    session.testsUsed = 0
    session.posted = false
    -- 天气在开局确定，整局不变；只记录与氛围，对隐藏状态的作用等待正式参数。
    local index = math.floor(session:NextRandom_() * #flow.weather) + 1
    local weather = assert(flow.weather[math.max(1, math.min(#flow.weather, index))], "天气索引越界")
    session.weatherId = weather.id
    return session
end

---@return number
function SessionFlow:NextRandom_()
    -- 32 位 LCG，与落点/力度使用同一套做法，不碰全局 math.random。
    self.randomState_ = (1664525 * self.randomState_ + 1013904223) % LCG_MODULUS
    return self.randomState_ / LCG_MODULUS
end

---@return integer
function SessionFlow:TestsUsed()
    return self.testsUsed
end

---@return integer
function SessionFlow:TestsRemaining()
    return self.flow.maxTests - self.testsUsed
end

---@return boolean
function SessionFlow:CanTest()
    return self.testsUsed < self.flow.maxTests
end

-- 发帖门槛：至少一次测试后才可提前发帖；用满总次数后必须发帖。
---@return string
function SessionFlow:PostingState()
    if self.testsUsed >= self.flow.maxTests then return SessionFlow.POST_REQUIRED end
    if self.testsUsed >= 1 then return SessionFlow.POST_OPTIONAL end
    return SessionFlow.POST_BLOCKED
end

-- 把一次落点结果解析为流程后果。刹车永远是正常计次路径；
-- 踩空与踩油门在作者给出规则前保持 unset，不由代码代选。
---@param outcome string
---@return string
function SessionFlow:ResolveOutcome(outcome)
    assert(outcome == "brake" or outcome == "throttle" or outcome == "missed",
        "未知的落点结果：" .. tostring(outcome))
    if outcome == "brake" then return SessionFlow.POLICY_CONSUME end
    local policy = self.flow.outcomePolicy[outcome]
    if not policy then error("缺少落点后果策略：" .. outcome, 2) end
    return policy
end

-- 记录一次尝试的输入：只需落点与力度结果，序号、车辆与天气由会话补。
---@param entry SessionTestInput
---@return SessionTestEntry
function SessionFlow:RecordTest(entry)
    local policy = self:ResolveOutcome(entry.outcome)
    if policy == SessionFlow.POLICY_UNSET then
        error("落点后果尚未确认，不能直接记入会话：" .. entry.outcome, 2)
    end
    local counted = policy == SessionFlow.POLICY_CONSUME
    if counted then
        assert(self:CanTest(), "总测试次数已用满，不能再记入新的测试")
        self.testsUsed = self.testsUsed + 1
    end
    ---@type SessionTestEntry
    local stored = {
        sequence = #self.tests + 1,
        testIndex = counted and self.testsUsed or nil,
        vehicleIndex = self.vehicleIndex,
        shoeId = entry.shoeId,
        weatherId = self.weatherId,
        outcome = entry.outcome,
        counted = counted,
        landingX = entry.landingX,
        landingY = entry.landingY,
        pedalCoverage = entry.pedalCoverage,
        shoeCoverage = entry.shoeCoverage,
        intentForce = entry.intentForce,
        force = entry.force,
        breakState = entry.breakState,
        source = entry.source or "unknown",
        reactionTime = entry.reactionTime,
        brakingTime = entry.brakingTime,
        brakingDistance = entry.brakingDistance,
        actualPedalForce = entry.actualPedalForce,
        completionStatus = entry.completionStatus,
        failureReason = entry.failureReason,
        structureState = entry.structureState,
        hiddenDamageBefore = entry.hiddenDamageBefore,
        hiddenDamageAfter = entry.hiddenDamageAfter,
    }
    self.tests[#self.tests + 1] = stored
    return CopyEntry(stored)
end

---@return SessionTestEntry?
function SessionFlow:LastTest()
    local entry = self.tests[#self.tests]
    if not entry then return nil end
    return CopyEntry(entry)
end

---@param breakState string
---@return boolean
function SessionFlow:IsBreaking(breakState)
    return breakState == SessionFlow.BREAK_ROOT or breakState == SessionFlow.BREAK_ROD
end

-- 换车是叙事动作：只有上一次结果真的断裂才可用，且不重置总次数与历史。
---@return boolean
function SessionFlow:CanChangeVehicle()
    local last = self.tests[#self.tests]
    if not last then return false end
    return self:IsBreaking(last.breakState)
end

---@return boolean
function SessionFlow:ChangeVehicle()
    if not self:CanChangeVehicle() then return false end
    self.vehicleIndex = self.vehicleIndex + 1
    return true
end

---@return integer
function SessionFlow:VehicleIndex()
    return self.vehicleIndex
end

---@param weatherId string
---@return table?
function SessionFlow:WeatherById(weatherId)
    for _, weather in ipairs(self.flow.weather) do
        if weather.id == weatherId then return weather end
    end
    return nil
end

---@return SessionWeather
function SessionFlow:Weather()
    local weather = self:WeatherById(self.weatherId)
    assert(weather, "当前天气配置缺失")
    return weather
end

---@return boolean
function SessionFlow:MarkPosted()
    if self:PostingState() == SessionFlow.POST_BLOCKED then return false end
    self.posted = true
    return true
end

---@return boolean
function SessionFlow:HasPosted()
    return self.posted
end

-- 供档案层使用的只读快照；不包含演出层内容，也不改写会话。
---@class SessionSnapshot
---@field flowVersion string
---@field seed number
---@field weatherId string
---@field vehicleIndex integer
---@field testsUsed integer
---@field maxTests integer
---@field postingState string
---@field posted boolean
---@field tests SessionTestEntry[]

---@return SessionSnapshot
function SessionFlow:Snapshot()
    local tests = {}
    for i, entry in ipairs(self.tests) do
        tests[i] = CopyEntry(entry) --[[@as SessionTestEntry]]
    end
    return {
        flowVersion = self.flow.version,
        seed = self.seed,
        weatherId = self.weatherId,
        vehicleIndex = self.vehicleIndex,
        testsUsed = self.testsUsed,
        maxTests = self.flow.maxTests,
        postingState = self:PostingState(),
        posted = self.posted,
        tests = tests,
    }
end

return SessionFlow
