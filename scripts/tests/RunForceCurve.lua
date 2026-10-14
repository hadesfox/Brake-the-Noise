-- P1.3 离线测试入口，只验证规则，不改变正式预览入口。
function Start()
    local ok, err = pcall(function()
        require("tests.FirstStep").Run()
        require("tests.Landing").Run()
        require("tests.ForceCurve").Run()
    end)
    if not ok then log:Write(LOG_ERROR, tostring(err)) end
    engine:Exit()
end
