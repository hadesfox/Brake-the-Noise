-- 加速阶段计时（纯逻辑，不依赖渲染）。
--
-- 只负责"从 0 加速到时速 100 km/h"的进度推进；不决定子弹时间、判定或演出。
-- 时长是骨架占位值：设计目标约 15 秒，这里用较短时长便于反复验证，
-- 不把占位时长当成最终节奏，也不靠暂停真实时间伪造"感觉用时"。
---@class AccelerationConfig
---@field durationSeconds number 加速到目标时速所需的秒数
---@field targetSpeed number 目标时速，km/h

---@class AccelerationModel
---@field config AccelerationConfig
---@field elapsed number 已推进的秒数
---@field speed number 当前时速，km/h
---@field running boolean
---@field completed boolean
local Acceleration = {}
Acceleration.__index = Acceleration

local function IsFinite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

---@param config AccelerationConfig
---@return AccelerationModel
function Acceleration.Create(config)
    assert(type(config) == "table", "加速配置必须是 table")
    assert(IsFinite(config.durationSeconds) and config.durationSeconds > 0,
        "加速时长必须是有限正数")
    assert(IsFinite(config.targetSpeed) and config.targetSpeed > 0,
        "目标时速必须是有限正数")
    local model = setmetatable({}, Acceleration)
    model.config = { durationSeconds = config.durationSeconds, targetSpeed = config.targetSpeed }
    model.elapsed = 0
    model.speed = 0
    model.running = false
    model.completed = false
    return model
end

---@return boolean
function Acceleration:Start()
    if self.running or self.completed then return false end
    self.elapsed = 0
    self.speed = 0
    self.running = true
    return true
end

---@param dt number
function Acceleration:Update(dt)
    assert(IsFinite(dt) and dt >= 0, "dt 必须为有限非负数")
    if not self.running or dt == 0 then return end
    local duration = self.config.durationSeconds
    self.elapsed = math.min(duration, self.elapsed + dt)
    local progress = self.elapsed / duration
    self.speed = self.config.targetSpeed * progress
    if self.elapsed >= duration then
        self.speed = self.config.targetSpeed
        self.running = false
        self.completed = true
    end
end

---@return number 0～1 的进度
function Acceleration:Progress()
    return math.min(1, self.elapsed / self.config.durationSeconds)
end

-- 重置到未发车状态，供同一会话内下一次测试复用。
function Acceleration:Reset()
    self.elapsed = 0
    self.speed = 0
    self.running = false
    self.completed = false
end

return Acceleration
