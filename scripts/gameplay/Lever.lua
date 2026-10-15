-- P1.2e 纯 Lua 几何：杆端支点与真实受力重心之间的力臂。
--
-- 支点、杆、踏板面共用同一份归一化场景几何（x 向右、y 向下，[0,1]^2），
-- 再统一映射到界面，所以窗口尺寸与 DPR 变化不会改变 L。
-- 这是游戏受力示意，不是从正面投影反推的三维扭矩。
--
--            pivot 支点（杆的一端）
--              *
--               \
--                \   杆
--                 \
--      ------------+----------  踏板面
--                  ^ 受力重心（真实交集面积重心，见 Landing.Contact）
--
-- 检测目的：给出受力重心到支点的距离，供 L 映射使用。
-- 边界：零接触没有受力重心，调用方不得进入载荷计算；距离本身与映射参数无关。

---@class LeverPivot
---@field pivotX number 支点，杆的一端，归一化场景坐标
---@field pivotY number

---@class LeverConfig : LeverPivot
---@field refDistance number 参考力臂尺度：L 在这个归一化距离取 1
---@field minArm number L 下限
---@field maxArm number L 上限

---@class LeverArm
---@field distance number 受力重心到支点的归一化场景距离
---@field l number 钳制后的相对力臂
---@field clamped boolean 是否被上下限钳制

local Lever = {}

---@param value any
---@return boolean
local function IsFinite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

---@param config LeverPivot
local function ValidatePivot(config)
    assert(type(config) == "table", "力臂配置必须为 table")
    assert(IsFinite(config.pivotX) and IsFinite(config.pivotY), "支点必须是有限数值")
    assert(config.pivotX >= 0 and config.pivotX <= 1
        and config.pivotY >= 0 and config.pivotY <= 1, "支点必须在归一化场景 [0,1] 内")
end

---@param config LeverConfig
local function ValidateMapping(config)
    ValidatePivot(config)
    assert(IsFinite(config.refDistance) and config.refDistance > 0, "参考力臂尺度必须是有限正数")
    assert(IsFinite(config.minArm) and IsFinite(config.maxArm), "L 上下限必须是有限数值")
    assert(config.minArm > 0 and config.maxArm >= config.minArm, "L 必须满足 0 < min <= max")
end

-- 纯几何距离：只依赖支点位置，不需要作者提供 L 范围与映射参数。
---@param config LeverPivot
---@param x number
---@param y number
---@return number
function Lever.Distance(config, x, y)
    ValidatePivot(config)
    assert(IsFinite(x) and IsFinite(y), "受力重心必须是有限数值")
    local dx, dy = x - config.pivotX, y - config.pivotY
    local distance = math.sqrt(dx * dx + dy * dy)
    assert(IsFinite(distance), "力臂距离溢出")
    return distance
end

-- 相对力臂：距离除以参考尺度后钳制到 [minArm, maxArm]。
---@param config LeverConfig
---@param x number
---@param y number
---@return LeverArm
function Lever.Arm(config, x, y)
    ValidateMapping(config)
    local distance = Lever.Distance(config, x, y)
    local raw = distance / config.refDistance
    local l = math.max(config.minArm, math.min(config.maxArm, raw))
    return { distance = distance, l = l, clamped = l ~= raw }
end

return Lever
