-- 正式数值的待填入口。false 明确表示作者尚未提供，不能用演示参数替代。
return {
    version = "pending-author-values",
    ready = false,
    explicit = {
        L = false, -- { min, max, ...落点映射 }
        A = false, -- { min, max, ...接触面积映射 }
        F = false, -- { min, max, ...心理曲线映射 }
    },
    hidden = {
        k1 = false, k2 = false, k3 = false, k4 = false,
        k5 = false, k6 = false, k7 = false, k8 = false,
    },
    psychology = { agitation = false, fatigue = false },
    sweep = false,
    shoes = false,
    threshold = false,
    braking = false,
    tokens = false,
    spread = false,
    opportunity = { maxTests = 3 }, -- 已定规则，不是待调数值。
}
