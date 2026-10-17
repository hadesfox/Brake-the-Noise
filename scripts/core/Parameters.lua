-- 参数校验只检查作者已给的结构，不计算或补造缺失值。
-- 按计划第 4.1 节 E 小节：旧的八项 k1～k8 强制连乘已取消，最终 K 仅为姿势。
-- 因此这里按职责分组，不再要求八项全部提供。
local Parameters = {}

local REQUIRED = {
    testing = {
        "explicit.L", "explicit.A", "explicit.F", "explicit.K",
        "landing.shoes", "landing.speed", "landing.habitWeight",
    },
    human = {
        "human.fatigue", "human.agitation", "human.temperature",
    },
    component = {
        "component.durability", "component.temperatureTolerance",
        "brake",
    },
    braking = {
        "braking.brakeCurve", "braking.resistance", "braking.roadLength",
    },
    posting = { "tokens", "spread" },
}

-- 需要 { min, max } 正数范围的组；其余待填项只检查非空 table。
local RANGED = {
    testing = true,
    human = true,
    component = true,
}

---@param config table
---@param path string
---@return any
local function readPath(config, path)
    local value = config
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

---@param config table
---@param group string
---@return string[]
function Parameters.Check(config, group)
    local issues = {}
    local paths = REQUIRED[group]
    assert(paths, "未知参数分组：" .. group)
    if type(config.version) ~= "string" or config.version == "" then
        issues[#issues + 1] = "缺少配置版本"
    end
    if readPath(config, "opportunity.maxTests") ~= 3 then
        issues[#issues + 1] = "总测试机会必须为 3 次"
    end
    for _, path in ipairs(paths) do
        local value = readPath(config, path)
        if type(value) ~= "table" or next(value) == nil then
            issues[#issues + 1] = "待作者提供：" .. path
        elseif RANGED[group] then
            -- 只对显式给了 min/max 的项做范围检查；未给范围的子项交由作者补。
            if type(value.min) == "number" or type(value.max) == "number" then
                if type(value.min) ~= "number" or type(value.max) ~= "number"
                    or value.min ~= value.min or value.max ~= value.max
                    or value.min <= 0 or value.max < value.min or value.max == math.huge then
                    issues[#issues + 1] = "无效范围：" .. path .. "（需有限正数 min <= max）"
                end
            end
        end
    end
    return issues
end

return Parameters
