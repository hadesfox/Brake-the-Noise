-- 仅供 P1.1～P1.3 开发验证；几何占位和种子不是正式鞋型、暗变量或系数配置。
return {
    version = "force-demo-3",
    title = "舆论刹车",
    sweep = {
        unitsPerSecond = 0.75, -- 已获作者确认的 P1.1 手感速度，归一化距离/秒。
        initialPhase = 0.15,
    },
    landingSeed = 20261014,
    forceSeed = 20261015,
    landing = {
        speed = 0.75,
        bounds = { minX = 0.08, maxX = 0.92, minY = 0.12, maxY = 0.88 },
        habitWeight = 0.35, -- 开发验证路径依赖；正式偏好强度仍待作者给值。
        pedal = { x = 0.38, y = 0.24, w = 0.24, h = 0.52 },
        shoes = {
            { id = "demo-flat", name = "宽底占位", parts = {
                { x = -0.11, y = -0.18, w = 0.22, h = 0.36 },
            } },
            { id = "demo-slim", name = "窄底占位", parts = {
                { x = -0.05, y = -0.18, w = 0.10, h = 0.36 },
            } },
            { id = "demo-heel", name = "分段底占位", parts = {
                { x = -0.08, y = -0.18, w = 0.16, h = 0.18 },
                { x = -0.025, y = 0.08, w = 0.05, h = 0.10 },
            } },
        },
    },
    -- 开发用心理曲线：只验证"两端大中间小 + 低平区宽度/上移/漂移/抖动"是否成立。
    -- 低平区、陡峭度、甜蜜点漂移和暴躁/疲劳影响强度均为占位值，正式数值待作者提供。
    force = {
        cursorSpeed = 0.62,
        flatHalfBase = 0.10,
        flatLevel = 0.12,
        peakLift = 0.70,
        rampWidth = 0.34,
        steepBase = 1.6,
        steepAgitation = 2.4,
        flatNarrow = 0.62,
        widenFatigue = 0.45,
        liftFatigue = 0.16,
        sweetBase = 0.5,
        sweetDrift = 0.18,
        jitterAmp = 0.035,
        jitterFreq1 = 5.5,
        jitterFreq2 = 13.0,
        speedAgitation = 0.55,
        speedFatigue = 0.35,
    },
}
