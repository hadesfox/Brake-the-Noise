-- 会话流程与页面占位配置（骨架阶段）。
--
-- 这里的内容只让「主界面 → 角色准备 → 驾驶舱 → 两轮测试 → 结算 → 发帖」这条流程跑起来，
-- 不是正式美术、正式服饰清单或正式规则：
--   · 服饰只做外观占位。已确认鞋子影响接触面积，其余服饰不擅自增加数值影响。
--   · 天气只用于窗外观察与记录，对疲劳/温度/暴躁的作用等待正式参数。
--   · 踩空与踩到油门的后果规则由实施计划第 4.1 节 B2 明确留空，这里保持 unset。
return {
    version = "flow-skeleton-1",
    -- 已确认规则：同局最多三次测试。该值不随流程配置调整，Session 会校验。
    maxTests = 3,
    -- 落点后果策略。取值：
    --   "unset"   —— 作者尚未确认，会话停在"后果待确认"占位页，不由 AI 代决定；
    --   "consume" —— 消耗一次测试机会，跳过第二轮并进入结算；
    --   "retry"   —— 不消耗机会，重新开始落点。
    outcomePolicy = {
        missed = "unset",
        throttle = "unset",
    },
    -- 骨架阶段的占位服饰：只做外观，不影响任何数值。
    character = {
        clothing = {
            { id = "cloth-placeholder-01", name = "上衣 01（占位）" },
            { id = "cloth-placeholder-02", name = "上衣 02（占位）" },
        },
        trousers = {
            { id = "trouser-placeholder-01", name = "裤子 01（占位）" },
            { id = "trouser-placeholder-02", name = "裤子 02（占位）" },
        },
    },
    -- 窗外天气：无选项，仅氛围与记录；三种天气不是最终清单。
    weather = {
        { id = "sunny", name = "晴", sky = { 122, 178, 226, 255 } },
        { id = "cloudy", name = "阴", sky = { 138, 148, 158, 255 } },
        { id = "rainy", name = "雨", sky = { 84, 96, 112, 255 } },
    },
}
