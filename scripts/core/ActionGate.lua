-- 多输入共享同一确认入口；锁按引擎帧号判断，不在 Update 中提前清除。
---@class ActionGate
---@field lastFrame number
---@field held table<number, boolean>
local Gate = {}
Gate.__index = Gate

---@return ActionGate
function Gate.Create()
    return setmetatable({ lastFrame = -1, held = {} }, Gate)
end

---@param frame number
---@return boolean
function Gate:Accept(frame)
    if frame == self.lastFrame then return false end
    self.lastFrame = frame
    return true
end

---@param key number
---@param isRepeat boolean
---@return boolean
function Gate:Press(key, isRepeat)
    if isRepeat or self.held[key] then return false end
    self.held[key] = true
    return true
end

---@param key number
function Gate:Release(key)
    self.held[key] = nil
end

function Gate:ClearHeld()
    self.held = {}
end

return Gate
