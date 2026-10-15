-- 仅作为官方运行时的开发验证入口，不从游戏菜单进入。
function Start()
    local ok, err = pcall(function()
        require("tests.FirstStep").Run()
    end)
    if not ok then log:Write(LOG_ERROR, tostring(err)) end
    engine:Exit()
end
