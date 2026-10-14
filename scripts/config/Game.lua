-- 正式数值的待填入口。false 明确表示作者尚未提供，不能用演示参数替代。
--
-- 已由作者确认、不属待填的项（此处只记录口径，不重复当作待填）：
--   · F 范围 80～1612 N，超出上限截断。
--   · 甜蜜区中心基准 0.50；最大漂移 ±0.18（全条 ±18 个百分点）；全宽 0.10～0.04。
--   · 最终载荷倍率 K 仅为姿势：T = F × L × A有效 × K姿势。
--   · 面积联合结构 A有效 = A集中(r踏板) × E传导(r鞋底)。
-- 旧 k1～k8 的去向见计划第 4.1 节 E 小节：k1/k2/k6/k8 删除，k3/k5 进入 F，
-- k4 保留为 K姿势，k7 分流为人体状态累积与部件承受余量 M。
return {
    version = "pending-author-values",
    ready = false,
    explicit = {
        L = false, -- { refDistance, min, max, 映射曲线 }；支点/杆/踏板/鞋型几何
        A = false, -- { 集中范围与曲线, 传导范围与曲线, 极小接触衰减 }
        F = false, -- { 渐变形状, 暴躁收窄映射, 疲劳减力系数, 漂移合成权重 }
        K = false, -- 仅姿势：座椅/姿势到施力效率的范围与映射
    },
    human = {
        fatigue = false, -- 独立状态：来源、累积/恢复速度、初始值
        agitation = false, -- 独立状态：来源、累积/恢复速度、初始值
        temperature = false, -- 一个游戏温度：目标、平滑常数、舒适区与不适累积
    },
    component = {
        durability = false, -- M0、损伤起点/增长曲线、变形与断裂比值边界
        temperatureTolerance = false, -- C温度(θ) 的方向/幅度与极端区
    },
    landing = {
        shoes = false,
        speed = false,
        habitWeight = false,
    },
    brake = false, -- 实际减速/停车用时规则，是否有独立完美刹车评价
    tokens = false,
    spread = false,
    opportunity = { maxTests = 3 }, -- 已定规则，不是待调数值。
}
