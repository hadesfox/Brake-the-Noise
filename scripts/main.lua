-- ============================================================================
-- 舆论游戏 (Opinion Game)
-- 基于 templates/scaffold-2d.lua 脚手架
-- UI 系统: urhox-libs/UI (Yoga Flexbox + NanoVG)
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 1. 全局变量声明
-- ============================================================================
---@type Widget?
local uiRoot_ = nil
local debugDraw_ = false

local CONFIG = {
    Title = "舆论游戏",
}

-- ============================================================================
-- 2. 生命周期函数
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    InitUI()
    CreateGameContent()
    CreateUI()
    SubscribeToEvents()

    print("=== Game Started: " .. CONFIG.Title .. " ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 3. 初始化辅助函数
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

-- ============================================================================
-- 4. 游戏逻辑 (AI 填充区域)
-- ============================================================================

function CreateGameContent()
    -- [TODO] 初始化舆论游戏状态：话题、玩家身份、舆论倾向值等
    print("Creating game content...")
end

function CreateUI()
    uiRoot_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        children = {
            CreatePlaceholderCard(),
            CreateDebugPanel(),
        }
    }

    UI.SetRoot(uiRoot_)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_Z then
        debugDraw_ = not debugDraw_
        if uiRoot_ then
            local debugPanel = uiRoot_:FindById("debugPanel")
            if debugPanel then
                debugPanel:SetVisible(debugDraw_)
            end
        end
    end
end

-- ============================================================================
-- 5. UI 构建辅助函数
-- ============================================================================

--- 脚手架占位卡片（正式开发时删除）
function CreatePlaceholderCard()
    return UI.Panel {
        id = "placeholderCard",
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 360,
                padding = 32,
                gap = 12,
                backgroundColor = { 30, 35, 50, 230 },
                borderRadius = 16,
                borderWidth = 1,
                borderColor = { 80, 90, 120, 100 },
                alignItems = "center",
                overflow = "hidden",
                pointerEvents = "auto",
                children = {
                    UI.Label {
                        text = CONFIG.Title,
                        fontSize = 20,
                        fontColor = { 255, 255, 255, 255 },
                    },
                    UI.Label {
                        text = "项目脚手架已就绪",
                        fontSize = 12,
                        fontColor = { 140, 160, 200, 180 },
                    },
                }
            }
        }
    }
end

--- 调试信息面板（按 Z 切换）
function CreateDebugPanel()
    return UI.Panel {
        id = "debugPanel",
        visible = false,
        position = "absolute",
        top = 10,
        left = 10,
        padding = 8,
        backgroundColor = { 0, 0, 0, 160 },
        borderRadius = 4,
        pointerEvents = "none",
        children = {
            UI.Label {
                text = "Debug Mode: ON",
                fontSize = 12,
                fontColor = { 255, 255, 255, 255 },
            },
        }
    }
end
