-- 纯逻辑模型：归一化游标的解析式往返运动，不依赖帧率和引擎对象。
---@class SweepModel
---@field phase number
---@field position number
---@field elapsed number
---@field speed number
---@field moving boolean
local Sweep = {}
Sweep.__index = Sweep

---@param phase number
---@return number
function Sweep.PositionAt(phase)
    local folded = phase % 2
    return folded <= 1 and folded or 2 - folded
end

---@param speed number
---@param initialPhase number
---@return SweepModel
function Sweep.Create(speed, initialPhase)
    assert(speed > 0, "游标速度必须大于零")
    local model = setmetatable({
        phase = initialPhase,
        position = Sweep.PositionAt(initialPhase),
        elapsed = 0,
        speed = speed,
        moving = true,
    }, Sweep)
    return model
end

---@param dt number
function Sweep:Update(dt)
    if not self.moving or dt <= 0 then return end
    self.elapsed = self.elapsed + dt
    self.phase = self.phase + dt * self.speed
    self.position = Sweep.PositionAt(self.phase)
end

---@return number
function Sweep:Lock()
    self.moving = false
    return self.position
end

---@param initialPhase number
function Sweep:Resume(initialPhase)
    self.phase = initialPhase
    self.position = Sweep.PositionAt(initialPhase)
    self.elapsed = 0
    self.moving = true
end

return Sweep
