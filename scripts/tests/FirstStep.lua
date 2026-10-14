-- 纯逻辑回归验证，不依赖渲染、网络或正式参数；由开发入口执行。
local Sweep = require("core.Sweep")
local Gate = require("core.ActionGate")
local Parameters = require("core.Parameters")
local GameConfig = require("config.Game")

local Tests = {}

function Tests.Run()
    local count = 0
    local function check(condition, description)
        assert(condition, "[首步验证失败] " .. description)
        count = count + 1
    end
    local function near(a, b) return math.abs(a - b) < 0.000001 end
    check(near(Sweep.PositionAt(0), 0), "左端")
    check(near(Sweep.PositionAt(1), 1), "右端")
    check(near(Sweep.PositionAt(1.5), 0.5), "返回半程")
    check(near(Sweep.PositionAt(2.2), 0.2), "跨整周期")
    check(near(Sweep.PositionAt(-0.2), 0.2), "负相位归一化")
    local large = Sweep.Create(0.75, 0.15)
    local small = Sweep.Create(0.75, 0.15)
    large:Update(4)
    for _ = 1, 240 do small:Update(1 / 60) end
    check(near(large.position, small.position), "不同帧率计算一致")
    check(large.position >= 0 and large.position <= 1, "大步长不越界")
    local locked = large:Lock()
    large:Update(100)
    check(near(large.position, locked), "锁定后不移动")
    large:Resume(large.phase)
    large:Update(0.1)
    check(not near(large.position, locked), "再次测量恢复运动")
    local gate = Gate.Create()
    check(gate:Press(1, false), "首次按键")
    check(not gate:Press(1, false), "按住不重复")
    gate:Release(1)
    check(not gate:Press(1, true), "系统 Repeat 不触发")
    check(gate:Press(1, false), "释放后可再次确认")
    check(gate:Accept(100), "本帧第一次动作")
    check(not gate:Accept(100), "同帧跨输入去重")
    check(gate:Accept(101), "下一帧可确认")
    gate:ClearHeld()
    check(gate:Press(1, false), "失焦清除按键闩锁")
    check(#Parameters.Check(GameConfig, "testing") > 0, "待填正式参数不能通过")
    check(#Parameters.Check(GameConfig, "hidden") > 0, "八个暗变量不可自拟")
    check(#Parameters.Check(GameConfig, "posting") > 0, "发帖参数未填显式阻塞")
    print("[首步验证] PASS，断言数=" .. count)
    return count
end

return Tests
