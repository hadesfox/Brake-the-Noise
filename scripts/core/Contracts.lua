-- 三幕交接的数据契约。这里只定义事实来源，不提前实现未开工的玩法。
---@class BrakeFactorRecord
---@field name string
---@field value number
---@field source string

---@class BrakeTestRecord
---@field testIndex integer
---@field vehicleIndex integer
---@field shoeId string
---@field landingX number
---@field overlapArea number
---@field peakF number
---@field torqueT number
---@field breakState string
---@field factors BrakeFactorRecord[]
---@field agitation number
---@field fatigue number
---@field feltSecondsRaw number
---@field feltSecondsShown number
---@field actualSeconds number

---@class BrakePostRecord
---@field titleTokenIds string[]
---@field contentTokenIds string[]
---@field originalPost string
---@field distortionDir string
---@field spreadPotential number
---@field sentAt number

---@class BrakeSessionRecord
---@field schemaVersion integer
---@field configVersion string
---@field seed integer
---@field tests BrakeTestRecord[]
---@field post BrakePostRecord?
---@field causalChain string[]
---@field endingId string?
---@field completed boolean

-- 第一幕 → 决策/发帖：完整 tests 历史，不只传最后一次断裂。
-- 第二幕 → 清算/传播：post 原文副本、方向、势能和 causalChain。
-- 完成局 → 档案：整个 session；测试索引和车辆索引分别保存。
-- 原文与历史记录一经提交不由演出层覆写；档案只接收 completed 的正式局。
return { schemaVersion = 1 }
