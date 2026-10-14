-- 仅供 P1.1～P1.3 开发验证；几何占位和种子不是正式鞋型、隐藏状态来源或映射参数。
--
-- 已由作者确认、可直接沿用的口径（不属占位）：
--   · 力度 F 范围 80～1612 N，超出上限截断。
--   · 甜蜜区中心基准 0.50，最大漂移 ±0.18（全条 ±18 个百分点）。
--   · 甜蜜区全宽 0.10～0.04（半宽 0.05～0.02），仅暴躁收窄。
--   · 疲劳减力、疲劳与暴躁共同参与漂移、连续渐变、两端为本状态最高力度。
-- 其余映射强度、曲线形状与抖动/变速幅度仍是开发占位值，正式数值待作者提供。
return {
    version = "force-demo-4",
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
    -- 杆端支点与力臂映射。支点位置是几何示意占位；refDistance/minArm/maxArm 待作者给值。
    lever = {
        pivotX = 0.5,
        pivotY = 0.06,
        refDistance = 0.4,
        minArm = 0.5,
        maxArm = 1.8,
    },
    -- 面积联合结构 A有效=A集中(r踏板)×E传导(r鞋底) 已确认；范围与曲线仍是占位值。
    contact = {
        concentrateMin = 1.0,
        concentrateMax = 2.6,
        concentrateCurve = 1.4,
        conductionFloor = 0.15,
        conductionFull = 1.0,
        conductionCurve = 0.9,
        conductionSoftStart = 0.25,
    },
    -- 开发用心理曲线：只验证"两端大中间小 + 仅暴躁收窄 + 疲劳减力 + 合成漂移"是否成立。
    force = {
        cursorSpeed = 0.62,
        intentLow = 120,
        intentHigh = 1600,
        forceMin = 80,
        forceMax = 1612,
        rampWidth = 0.34,
        steepBase = 1.6,
        steepAgitation = 2.4,
        sweetBase = 0.5,
        sweetDriftMax = 0.18,
        agitationDriftWeight = 1.0,
        fatigueDriftWeight = 0.6,
        sweetHalfMax = 0.05,
        sweetHalfMin = 0.02,
        sweetNarrowAgitation = 0.6,
        fatigueForceCut = 0.35,
        jitterAmp = 0.035,
        jitterFreq1 = 5.5,
        jitterFreq2 = 13.0,
        speedAgitation = 0.55,
        speedFatigue = 0.35,
    },
}
