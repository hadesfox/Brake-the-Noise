-- 纯逻辑制动模拟：输入 F×E传导、BrakeCurve 与阻力参数，输出可复现的速度、距离、制动用时和停车判定。
-- 这是成绩标尺，与 3D 表现分离。
--
-- 设计依据：方案A 第22章 + 实施计划 4.2 节
--
-- 输入：
--   pedalForce: 实际作用到制动通道的力 F×E传导（牛顿）
--   brakeCurve: { minF, maxF, minA, maxA } 制动力度到减速度映射
--   resistance: { rolling, air, slope } 阻力参数
--   initialSpeed: 初始速度（km/h）
--   roadLength: 道路长度（米）
--   structureBroken: 是否断裂（断裂时主动制动力立即归零）
--
-- 输出：
--   brakingTime: 100-0制动用时（秒），主成绩
--   brakingDistance: 制动距离（米）
--   finalSpeed: 最终速度（km/h）
--   stoppedInRoad: 是否在道路内停车（boolean）

local BrakingSimulation = {}

--- 将制动踏板力映射为减速度（m/s²）
---@param pedalForce number 牛顿
---@param brakeCurve table { minF, maxF, minA, maxA }
---@return number 减速度 m/s²
local function mapForceToDeceleration(pedalForce, brakeCurve)
    if pedalForce <= brakeCurve.minF then
        return brakeCurve.minA
    elseif pedalForce >= brakeCurve.maxF then
        return brakeCurve.maxA
    else
        local ratio = (pedalForce - brakeCurve.minF) / (brakeCurve.maxF - brakeCurve.minF)
        return brakeCurve.minA + ratio * (brakeCurve.maxA - brakeCurve.minA)
    end
end

--- 模拟制动过程（欧拉积分，固定时间步长）
---@param params table 输入参数
---@return table 输出结果
function BrakingSimulation.simulate(params)
    local pedalForce = params.pedalForce or 0
    local brakeCurve = params.brakeCurve or { minF = 80, maxF = 1612, minA = 1.0, maxA = 10.0 }
    local resistance = params.resistance or { rolling = 0.015, air = 0.3, slope = 0 }
    local initialSpeed = params.initialSpeed or 100 -- km/h
    local roadLength = params.roadLength or 200 -- 米
    local structureBroken = params.structureBroken or false

    -- 单位转换
    local v = initialSpeed / 3.6 -- m/s
    local distance = 0
    local time = 0
    local dt = 0.01 -- 10ms 步长

    -- 断裂时主动制动力归零
    local activeBrakeA = structureBroken and 0 or mapForceToDeceleration(pedalForce, brakeCurve)

    while v > 0.01 and distance < roadLength do
        -- 阻力减速度（简化模型）
        local rollingA = resistance.rolling * 9.8
        local airA = resistance.air * v * v / 100
        local slopeA = resistance.slope * 9.8

        local totalA = activeBrakeA + rollingA + airA - slopeA

        -- 速度更新
        v = v - totalA * dt
        if v < 0 then v = 0 end

        -- 距离更新
        distance = distance + v * dt
        time = time + dt
    end

    return {
        brakingTime = time,
        brakingDistance = distance,
        finalSpeed = v * 3.6, -- km/h
        stoppedInRoad = distance < roadLength
    }
end

return BrakingSimulation
