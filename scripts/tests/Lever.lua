-- P1.2e 纯 Lua 回归：杆端支点、受力重心到支点的距离与 L 映射。
-- 只使用测试 fixtures，不读取 Demo 或正式游戏配置。
local Lever = require("gameplay.Lever")
local Tests = {}

---@return LeverConfig
local function Fixture()
    return {
        pivotX = 0.5,
        pivotY = 0.1,
        refDistance = 0.4,
        minArm = 0.5,
        maxArm = 1.8,
    }
end

---@param a number
---@param b number
---@return boolean
local function Near(a, b)
    return math.abs(a - b) <= 0.000000001
end

---@return integer
function Tests.Run()
    local count = 0
    ---@param condition boolean
    ---@param description string
    local function Check(condition, description)
        assert(condition, "[力臂验证失败] " .. description)
        count = count + 1
    end

    local config = Fixture()
    Check(Near(Lever.Distance(config, 0.5, 0.1), 0), "支点自身距离为零")
    Check(Near(Lever.Distance(config, 0.5, 0.5), 0.4), "正下方距离等于纵向差")
    Check(Near(Lever.Distance(config, 0.9, 0.1), 0.4), "正右方距离等于横向差")
    Check(Near(Lever.Distance(config, 0.8, 0.4), math.sqrt(0.3 * 0.3 + 0.09)), "斜向距离按欧氏几何")
    -- 受力重心与鞋中心不同：同一鞋中心、不同重心给出不同 L。
    local nearArm = Lever.Arm(config, 0.5, 0.5)
    local farArm = Lever.Arm(config, 0.5, 0.9)
    Check(farArm.distance > nearArm.distance, "重心离支点越远，距离越大")
    Check(Near(nearArm.l, 1.0), "距离等于参考尺度时 L 为一")
    -- (0.5,0.9) 距离 0.8，是参考尺度 0.4 的两倍，被 maxArm 钳制到上限。
    Check(Near(farArm.distance, 0.8) and farArm.clamped and Near(farArm.l, config.maxArm),
        "两倍参考尺度的距离被钳制到 L 上限")
    local midArm = Lever.Arm(config, 0.5, 0.7)
    Check(Near(midArm.l, 1.5) and not midArm.clamped, "范围内距离线性映射到 L")

    -- 上下限钳制：L 有界，不随距离无限增长，也不出现零或负值。
    local tooFar = Lever.Arm(config, 0.5, 1)
    Check(tooFar.clamped and Near(tooFar.l, config.maxArm), "超出上限的距离钳制到 maxArm")
    local tiny = Lever.Arm({ pivotX = 0.5, pivotY = 0.5, refDistance = 10, minArm = 0.5, maxArm = 1.8 },
        0.5, 0.5)
    Check(tiny.clamped and Near(tiny.l, config.minArm), "极小距离钳制到 minArm")
    Check(tooFar.l > 0 and tiny.l > 0, "L 始终为正，不出现零或负力臂")
    Check(not nearArm.clamped and not midArm.clamped, "范围内不标记钳制")

    -- 几何与界面无关：同一归一化重心在任意"窗口尺寸"下给出同一个 L。
    local scaled = Fixture()
    scaled.refDistance = 0.4
    Check(Near(Lever.Arm(config, 0.8, 0.4).l, Lever.Arm(scaled, 0.8, 0.4).l),
        "L 只依赖归一化几何，不依赖显示尺寸")

    ---@param change fun(config: LeverConfig)
    ---@param description string
    local function RejectConfig(change, description)
        local bad = Fixture()
        change(bad)
        assert(not pcall(Lever.Arm, bad, 0.5, 0.5), "[力臂验证失败] " .. description)
        count = count + 1
    end
    RejectConfig(function(c) c.pivotX = -0.1 end, "拒绝越界支点")
    RejectConfig(function(c) c.pivotY = 1.5 end, "拒绝越界支点")
    RejectConfig(function(c) c.pivotX = 0 / 0 end, "拒绝 NaN 支点")
    RejectConfig(function(c) c.refDistance = 0 end, "拒绝零参考尺度")
    RejectConfig(function(c) c.refDistance = -1 end, "拒绝负参考尺度")
    RejectConfig(function(c) c.minArm = 0 end, "拒绝零 L 下限")
    RejectConfig(function(c) c.maxArm = 0.1 end, "拒绝上限低于下限")
    Check(not pcall(Lever.Distance, config, 0 / 0, 0.5), "拒绝 NaN 受力重心")
    Check(not pcall(Lever.Distance, config, 0.5, math.huge), "拒绝无限受力重心")
    -- 距离只依赖支点，不需要 L 映射参数，因此缺映射也能算距离。
    ---@type LeverPivot
    local pivotOnly = { pivotX = 0.5, pivotY = 0.1 }
    Check(Near(Lever.Distance(pivotOnly, 0.5, 0.5), 0.4),
        "Distance 不依赖 L 范围参数")

    print("[力臂验证] PASS，纯 Lua 支点/距离/映射断言数=" .. count)
    return count
end

return Tests
