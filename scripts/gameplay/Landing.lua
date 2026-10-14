-- P1.2 纯 Lua 模型：归一化二维恒速折线与矩形鞋底的真实接触面积。
-- 不依赖引擎、UI、正式参数或全局随机数；开发 Demo 提供全部业务配置。
--
-- 几何约定（x 向右，y 向下；鞋中心 C 可位于 bounds 任一点）：
--       pedal: (x,y) +-------+       shoe.parts: 相对 C 的左上角与 w/h
--                    | 接触  |                   +---+---+
--                    +-------+                   | C |   |
--                                                +---+---+
-- 检测目的：逐 part 裁剪 pedal，返回面积和交集矩形，供锁点记录/准确渲染。
-- 边界：只共边/共角不接触；鞋缺口不算面积；鞋矩形内部重叠拒绝双算。

---@class LandingRect
---@field x number
---@field y number
---@field w number
---@field h number

---@class LandingBounds
---@field minX number
---@field maxX number
---@field minY number
---@field maxY number

---@class LandingShoe
---@field id string
---@field name string
---@field parts LandingRect[]

---@class LandingConfig
---@field speed number 归一化欧氏距离/秒
---@field bounds LandingBounds 鞋中心运动边界，不是整个鞋底的包围范围
---@field habitWeight number 零到一，下一目标向上次锁点的插值权重
---@field pedal LandingRect
---@field shoes LandingShoe[]

---@class LandingContact
---@field area number
---@field shoeArea number
---@field pedalArea number
---@field shoeCoverage number
---@field pedalCoverage number
---@field intersections LandingRect[] 归一化场景坐标，不是鞋中心的相对坐标
---@field hasContact boolean 是否有真实接触；零接触时下面两个重心为空
---@field centroidX number? 真实交集面积重心，受力位置；零接触为空
---@field centroidY number?
---@field shoeCentroidX number? 鞋底几何中心，玩家操作落点；零接触为空
---@field shoeCentroidY number?

---@class LandingRecord
---@field x number 鞋中心，玩家操作落点
---@field y number
---@field shoeId string
---@field area number
---@field shoeArea number
---@field pedalArea number
---@field shoeCoverage number 交集面积 / 鞋底总面积，传导效率输入
---@field pedalCoverage number 交集面积 / 踏板面积，载荷集中输入
---@field hasContact boolean
---@field centroidX number? 受力重心，与鞋中心分开记录
---@field centroidY number?
---@field shoeCentroidX number? 鞋底几何中心
---@field shoeCentroidY number?
---@field elapsed number 当前测量的有效运动时间，不含暂停和历史测量
---@field seed number 初始种子，不是已推进的 LCG 状态
---@field source string

---@class LandingModel
---@field config LandingConfig 配置的深拷贝
---@field x number
---@field y number
---@field moving boolean
---@field elapsed number
---@field shoeIndex integer
---@field seed number
---@field records LandingRecord[]
---@field previousX number?
---@field previousY number?
---@field targetX number 当前线段的目标，位于 bounds 内
---@field targetY number
---@field randomState_ number
---@field elapsedCorrection_ number
---@field segmentX_ number
---@field segmentY_ number
---@field segmentStart_ number
---@field segmentDuration_ number
local Landing = {}
Landing.__index = Landing

local LCG_MODULUS = 4294967296

---@param value number
---@return boolean
local function IsFinite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

---@param rect LandingRect
---@param allowZero boolean
local function ValidateRect(rect, allowZero)
    assert(type(rect) == "table", "矩形必须为 table")
    assert(IsFinite(rect.x) and IsFinite(rect.y), "矩形坐标必须是有限数值")
    assert(IsFinite(rect.w) and IsFinite(rect.h), "矩形宽高必须是有限数值")
    assert(rect.w >= 0 and rect.h >= 0, "矩形宽高不能为负")
    assert(allowZero or (rect.w > 0 and rect.h > 0), "配置矩形宽高必须大于零")
    assert(IsFinite(rect.x + rect.w) and IsFinite(rect.y + rect.h), "矩形端点溢出")
    assert(IsFinite(rect.w * rect.h), "矩形面积溢出")
    if not allowZero then
        assert(rect.x + rect.w > rect.x and rect.y + rect.h > rect.y
            and rect.w * rect.h > 0, "配置矩形太小，无法表示正面积")
    end
end

---@param items table
---@return integer
local function ArrayCount(items)
    assert(type(items) == "table", "数组必须为 table")
    local count = 0
    for key in pairs(items) do
        assert(type(key) == "number" and key >= 1 and key == math.floor(key), "数组须从 1 连续索引")
        count = count + 1
    end
    for index = 1, count do
        assert(items[index] ~= nil, "数组不能有空洞")
    end
    return count
end

---@param shoe LandingShoe
---@param allowZero boolean
local function ValidateParts(shoe, allowZero)
    assert(type(shoe) == "table", "鞋底必须为 table")
    local count = ArrayCount(shoe.parts)
    assert(allowZero or count > 0, "配置鞋底至少需要一个矩形")
    for index = 1, count do
        local part = assert(shoe.parts[index], "鞋底矩形索引缺失")
        ValidateRect(part, allowZero)
        for otherIndex = 1, index - 1 do
            local other = assert(shoe.parts[otherIndex], "鞋底矩形索引缺失")
            local overlapW = math.min(part.x + part.w, other.x + other.w) - math.max(part.x, other.x)
            local overlapH = math.min(part.y + part.h, other.y + other.h) - math.max(part.y, other.y)
            assert(overlapW <= 0 or overlapH <= 0, "鞋底矩形内部不能重叠（共边允许）")
        end
    end
end

---@param config LandingConfig
---@param seed number
local function ValidateConfig(config, seed)
    assert(type(config) == "table", "Landing 配置必须为 table")
    assert(IsFinite(config.speed) and config.speed > 0, "移动速度必须是有限正数")
    assert(IsFinite(config.habitWeight) and config.habitWeight >= 0 and config.habitWeight <= 1,
        "习惯权重必须在 [0,1]")
    assert(IsFinite(seed) and seed == math.floor(seed) and seed >= 0 and seed < LCG_MODULUS,
        "种子必须是 [0,2^32) 的整数")
    local bounds = config.bounds
    assert(type(bounds) == "table", "移动边界必须为 table")
    assert(IsFinite(bounds.minX) and IsFinite(bounds.maxX)
        and IsFinite(bounds.minY) and IsFinite(bounds.maxY), "边界必须是有限数值")
    assert(bounds.minX >= 0 and bounds.maxX <= 1 and bounds.minY >= 0 and bounds.maxY <= 1,
        "移动边界必须在归一化范围 [0,1] 内")
    assert(bounds.maxX > bounds.minX and bounds.maxY > bounds.minY, "二维移动边界必须有正宽高")
    local diagonal = math.sqrt((bounds.maxX - bounds.minX) ^ 2 + (bounds.maxY - bounds.minY) ^ 2)
    assert(diagonal > 0 and IsFinite(diagonal / config.speed) and diagonal / config.speed > 0,
        "速度或边界尺度无法表示有效线段时间")
    ValidateRect(config.pedal, false)
    local count = ArrayCount(config.shoes)
    assert(count > 0, "至少需要一双鞋")
    local ids = {}
    for _, shoe in ipairs(config.shoes) do
        assert(type(shoe) == "table", "鞋配置必须为 table")
        assert(type(shoe.id) == "string" and shoe.id ~= "", "鞋 id 必须是非空字符串")
        assert(type(shoe.name) == "string" and shoe.name ~= "", "鞋名称必须是非空字符串")
        assert(not ids[shoe.id], "鞋 id 不能重复")
        ids[shoe.id] = true
        ValidateParts(shoe, false)
    end
end

---@param rect LandingRect
---@return LandingRect
local function CopyRect(rect)
    return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

---@param config LandingConfig
---@return LandingConfig
local function CopyConfig(config)
    ---@type LandingShoe[]
    local shoes = {}
    for _, shoe in ipairs(config.shoes) do
        ---@type LandingRect[]
        local parts = {}
        for _, part in ipairs(shoe.parts) do parts[#parts + 1] = CopyRect(part) end
        shoes[#shoes + 1] = { id = shoe.id, name = shoe.name, parts = parts }
    end
    return {
        speed = config.speed,
        bounds = { minX = config.bounds.minX, maxX = config.bounds.maxX,
            minY = config.bounds.minY, maxY = config.bounds.maxY },
        habitWeight = config.habitWeight,
        pedal = CopyRect(config.pedal),
        shoes = shoes,
    }
end

---@param area number
---@param total number
---@return number
local function Coverage(area, total)
    if total <= 0 then return 0 end
    return math.max(0, math.min(1, area / total))
end

-- 受力重心：Σ(交集块面积 × 块中心) / 总交集面积，只按真实交集加权。
-- 分段鞋底的缺口与包围盒不参与，所以小鞋底充分踩中与大鞋底一角踩中不会得到同一重心。
---@param intersections LandingRect[]
---@param area number
---@return number? centroidX
---@return number? centroidY
local function ContactCentroid(intersections, area)
    if area <= 0 then return nil, nil end
    local sumX = 0.0
    local sumY = 0.0
    for _, block in ipairs(intersections) do
        local weight = block.w * block.h
        sumX = sumX + weight * (block.x + block.w / 2)
        sumY = sumY + weight * (block.y + block.h / 2)
    end
    assert(IsFinite(sumX) and IsFinite(sumY), "交集加权重心溢出")
    return sumX / area, sumY / area
end

-- 鞋底几何中心：只按真实鞋块的面积加权，不含鞋底缺口。
---@param shoe LandingShoe
---@param x number
---@param y number
---@return number? centroidX
---@return number? centroidY
local function ShoeCentroid(shoe, x, y)
    local total = 0.0
    local sumX = 0.0
    local sumY = 0.0
    for _, part in ipairs(shoe.parts) do
        local weight = part.w * part.h
        if weight > 0 then
            total = total + weight
            sumX = sumX + weight * (x + part.x + part.w / 2)
            sumY = sumY + weight * (y + part.y + part.h / 2)
        end
    end
    if total <= 0 then return nil, nil end
    assert(IsFinite(sumX) and IsFinite(sumY), "鞋底加权中心溢出")
    return sumX / total, sumY / total
end

-- Contact 允许零尺寸/空 parts 作为退化几何（比例均安全为零）；Create 拒绝此类配置。
---@param pedal LandingRect
---@param shoe LandingShoe
---@param x number
---@param y number
---@return LandingContact
function Landing.Contact(pedal, shoe, x, y)
    ValidateRect(pedal, true)
    ValidateParts(shoe, true)
    assert(IsFinite(x) and IsFinite(y), "鞋中心必须是有限数值")
    ---@type LandingRect[]
    local intersections = {}
    ---@type number
    local area = 0
    ---@type number
    local shoeArea = 0
    for _, part in ipairs(shoe.parts) do
        shoeArea = shoeArea + part.w * part.h
        local partX, partY = x + part.x, y + part.y
        assert(IsFinite(partX) and IsFinite(partY)
            and IsFinite(partX + part.w) and IsFinite(partY + part.h), "鞋底平移后端点溢出")
        local left, top = math.max(pedal.x, partX), math.max(pedal.y, partY)
        local right = math.min(pedal.x + pedal.w, partX + part.w)
        local bottom = math.min(pedal.y + pedal.h, partY + part.h)
        local w, h = math.max(0, right - left), math.max(0, bottom - top)
        if w > 0 and h > 0 then
            intersections[#intersections + 1] = { x = left, y = top, w = w, h = h }
            area = area + w * h
        end
    end
    assert(IsFinite(shoeArea) and IsFinite(area), "鞋底累计面积溢出")
    local pedalArea = pedal.w * pedal.h
    local centroidX, centroidY = ContactCentroid(intersections, area)
    local shoeCentroidX, shoeCentroidY = ShoeCentroid(shoe, x, y)
    return { area = area, shoeArea = shoeArea, pedalArea = pedalArea,
        shoeCoverage = Coverage(area, shoeArea), pedalCoverage = Coverage(area, pedalArea),
        intersections = intersections, hasContact = area > 0,
        centroidX = centroidX, centroidY = centroidY,
        shoeCentroidX = shoeCentroidX, shoeCentroidY = shoeCentroidY }
end

---@param record LandingRecord
---@return LandingRecord
local function CopyRecord(record)
    return { x = record.x, y = record.y, shoeId = record.shoeId,
        area = record.area, shoeArea = record.shoeArea, pedalArea = record.pedalArea,
        shoeCoverage = record.shoeCoverage, pedalCoverage = record.pedalCoverage,
        hasContact = record.hasContact, centroidX = record.centroidX, centroidY = record.centroidY,
        shoeCentroidX = record.shoeCentroidX, shoeCentroidY = record.shoeCentroidY,
        elapsed = record.elapsed, seed = record.seed, source = record.source }
end

---@param config LandingConfig
---@param seed number
---@return LandingModel
function Landing.Create(config, seed)
    ValidateConfig(config, seed)
    local model = setmetatable({}, Landing)
    model:init(config, seed)
    return model
end

---@param config LandingConfig
---@param seed number
function Landing:init(config, seed)
    self.config = CopyConfig(config)
    self.seed = seed
    self.randomState_ = seed
    self.x = (config.bounds.minX + config.bounds.maxX) / 2
    self.y = (config.bounds.minY + config.bounds.maxY) / 2
    self.moving = false
    self.elapsed = 0
    self.elapsedCorrection_ = 0
    self.shoeIndex = 1
    self.records = {}
    self.previousX = nil
    self.previousY = nil
    self.targetX, self.targetY = self.x, self.y
    self.segmentX_, self.segmentY_ = self.x, self.y
    self.segmentStart_, self.segmentDuration_ = 0, 0
    self:Start()
end

---@return number
function Landing:NextRandom_()
    -- 32 位 LCG：乘积小于 2^53，Lua integer 和 double 都能准确计算，不碰 math.random。
    self.randomState_ = (1664525 * self.randomState_ + 1013904223) % LCG_MODULUS
    return self.randomState_ / LCG_MODULUS
end

---@param startedAt number
function Landing:NextSegment_(startedAt)
    local bounds = self.config.bounds
    local randomX = bounds.minX + (bounds.maxX - bounds.minX) * self:NextRandom_()
    local randomY = bounds.minY + (bounds.maxY - bounds.minY) * self:NextRandom_()
    local targetX, targetY = randomX, randomY
    local previousX, previousY = self.previousX, self.previousY
    if previousX ~= nil and previousY ~= nil then
        local weight = self.config.habitWeight
        targetX = (1 - weight) * randomX + weight * previousX
        targetY = (1 - weight) * randomY + weight * previousY
    end
    local dx, dy = targetX - self.x, targetY - self.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance == 0 or startedAt + distance / self.config.speed <= startedAt then
        -- weight=1 且刚锁点时，插值目标恰等于当前位置，不能循环重抽同一点。
        -- 做一次确定性半程探索（至最远角的中点），下一段仍回到 previous。
        -- 不引入隐藏习惯参数、不额外抽随机数，且探索目标仍在边界内。
        local cornerX = self.x <= (bounds.minX + bounds.maxX) / 2 and bounds.maxX or bounds.minX
        local cornerY = self.y <= (bounds.minY + bounds.maxY) / 2 and bounds.maxY or bounds.minY
        targetX, targetY = (self.x + cornerX) / 2, (self.y + cornerY) / 2
        local fallbackX, fallbackY = targetX - self.x, targetY - self.y
        distance = math.sqrt(fallbackX * fallbackX + fallbackY * fallbackY)
    end
    local duration = distance / self.config.speed
    assert(duration > 0 and IsFinite(duration) and startedAt + duration > startedAt,
        "线段时间无法表示，检查速度/边界尺度")
    self.segmentX_, self.segmentY_ = self.x, self.y
    self.targetX, self.targetY = targetX, targetY
    self.segmentStart_, self.segmentDuration_ = startedAt, duration
end

---@param dt number
function Landing:Update(dt)
    assert(IsFinite(dt) and dt >= 0, "dt 必须为有限非负数")
    if not self.moving or dt == 0 then return end
    -- 补偿时间累加；位置按整段起点与绝对时间求值，不逐帧累加坐标。
    local adjusted = dt - self.elapsedCorrection_
    local elapsed = self.elapsed + adjusted
    assert(IsFinite(elapsed), "累计运动时间溢出")
    self.elapsedCorrection_ = (elapsed - self.elapsed) - adjusted
    self.elapsed = elapsed
    while self.elapsed >= self.segmentStart_ + self.segmentDuration_ do
        local endpointTime = self.segmentStart_ + self.segmentDuration_
        self.x, self.y = self.targetX, self.targetY
        self:NextSegment_(endpointTime)
    end
    local fraction = math.max(0, math.min(1, (self.elapsed - self.segmentStart_) / self.segmentDuration_))
    self.x = self.segmentX_ + (self.targetX - self.segmentX_) * fraction
    self.y = self.segmentY_ + (self.targetY - self.segmentY_) * fraction
end

-- 只能锁定后换鞋；无效索引/运动中拒绝，不修改中心、时间、随机状态或历史。
---@param index number
---@return boolean
function Landing:SelectShoe(index)
    if self.moving or not IsFinite(index) or index ~= math.floor(index)
        or index < 1 or index > #self.config.shoes then return false end
    self.shoeIndex = math.floor(index)
    return true
end

---@param source string?
---@return LandingRecord?
function Landing:Lock(source)
    if not self.moving then return nil end
    assert(source == nil or (type(source) == "string" and source ~= ""), "输入来源必须是非空字符串")
    local shoe = self.config.shoes[self.shoeIndex]
    assert(shoe ~= nil, "所选鞋配置缺失")
    local contact = Landing.Contact(self.config.pedal, shoe, self.x, self.y)
    ---@type LandingRecord
    local record = { x = self.x, y = self.y, shoeId = shoe.id,
        area = contact.area, shoeArea = contact.shoeArea, pedalArea = contact.pedalArea,
        shoeCoverage = contact.shoeCoverage, pedalCoverage = contact.pedalCoverage,
        hasContact = contact.hasContact, centroidX = contact.centroidX, centroidY = contact.centroidY,
        shoeCentroidX = contact.shoeCentroidX, shoeCentroidY = contact.shoeCentroidY,
        elapsed = self.elapsed, seed = self.seed, source = source or "unknown" }
    self.moving = false
    self.previousX, self.previousY = self.x, self.y
    self.records[#self.records + 1] = record
    -- 返回另一份快照，外部修改返回值不会改写已存历史。
    return CopyRecord(record)
end

-- 初次 Create 已调用 Start；已 moving 时调用无副作用。
-- 新测量只重置 elapsed，从当前中心续测，保留种子流、鞋选择、习惯点和 records。
---@return boolean
function Landing:Start()
    if self.moving then return false end
    self.elapsed, self.elapsedCorrection_ = 0, 0
    self:NextSegment_(0)
    self.moving = true
    return true
end

---@return boolean
function Landing:Resume()
    return self:Start()
end

return Landing
