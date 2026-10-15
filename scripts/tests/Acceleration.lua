-- 加速阶段纯逻辑验证：进度推进、完成边界、重置、坏配置拒绝。
local Acceleration = require("core.Acceleration")

local Tests = {}

function Tests.Run()
    local count = 0
    local function check(condition, description)
        assert(condition, "[加速验证失败] " .. description)
        count = count + 1
    end
    local function near(a, b) return math.abs(a - b) < 0.000001 end

    local model = Acceleration.Create({ durationSeconds = 2, targetSpeed = 100 })
    check(model.speed == 0, "未发车时时速为 0")
    check(model.running == false, "未发车时不运行")
    check(model.completed == false, "未发车时未完成")
    check(model:Start() == true, "可以发车")
    check(model:Start() == false, "重复发车无效")

    model:Update(1)
    check(near(model.speed, 50), "过半时长时速为 50")
    check(near(model:Progress(), 0.5), "过半时长进度为 0.5")
    check(model.completed == false, "中途未完成")

    model:Update(1)
    check(near(model.speed, 100), "到时达到目标时速")
    check(model.completed == true, "到时标记完成")
    check(model.running == false, "完成后停止运行")

    -- 超过剩余时长不应越过目标时速。
    local overshoot = Acceleration.Create({ durationSeconds = 2, targetSpeed = 100 })
    overshoot:Start()
    overshoot:Update(10)
    check(near(overshoot.speed, 100), "超长时间不越过目标时速")
    check(overshoot.completed == true, "超长时间仍然完成")

    -- 跨帧率一致：大步长与多小步得到相同结果。
    local big = Acceleration.Create({ durationSeconds = 3, targetSpeed = 100 })
    local small = Acceleration.Create({ durationSeconds = 3, targetSpeed = 100 })
    big:Start()
    small:Start()
    big:Update(1.5)
    for _ = 1, 90 do small:Update(1 / 60) end
    check(near(big.speed, small.speed), "不同帧率进度一致")

    -- 重置后可再次发车；重置不改变配置。
    model:Reset()
    check(model.speed == 0 and model.elapsed == 0, "重置清空进度")
    check(model.completed == false and model.running == false, "重置清空状态")
    check(model.config.durationSeconds == 2, "重置不改写配置")
    check(model:Start() == true, "重置后可以再次发车")

    -- dt 为 0 不推进；负值被拒绝。
    local idle = Acceleration.Create({ durationSeconds = 2, targetSpeed = 100 })
    idle:Start()
    idle:Update(0)
    check(idle.elapsed == 0, "dt 为 0 不推进")
    check(not pcall(idle.Update, idle, -1), "负 dt 被拒绝")

    -- 坏配置拒绝。
    check(not pcall(Acceleration.Create, { durationSeconds = 0, targetSpeed = 100 }),
        "零时长被拒绝")
    check(not pcall(Acceleration.Create, { durationSeconds = 2, targetSpeed = 0 }),
        "零目标时速被拒绝")
    check(not pcall(Acceleration.Create, { durationSeconds = -1, targetSpeed = 100 }),
        "负时长被拒绝")

    print("[加速验证] PASS，断言数=" .. count)
    return count
end

return Tests
