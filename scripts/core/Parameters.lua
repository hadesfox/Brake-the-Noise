-- 参数校验只检查作者已给的结构，不计算或补造缺失值。
local Parameters = {}

local REQUIRED = {
    testing = {
        "explicit.L", "explicit.A", "explicit.F", "sweep", "shoes",
        "psychology.agitation", "psychology.fatigue",
    },
    hidden = {
        "hidden.k1", "hidden.k2", "hidden.k3", "hidden.k4",
        "hidden.k5", "hidden.k6", "hidden.k7", "hidden.k8",
        "threshold", "braking",
    },
    posting = { "tokens", "spread" },
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
        elseif path:match("^explicit%.") or path:match("^hidden%.") then
            if type(value.min) ~= "number" or type(value.max) ~= "number"
                or value.min ~= value.min or value.max ~= value.max
                or value.min <= 0 or value.max < value.min or value.max == math.huge then
                issues[#issues + 1] = "无效范围：" .. path .. "（需有限正数 min <= max）"
            end
        end
    end
    return issues
end

return Parameters
