-- 仅供 P1.1 手感测量，不是正式游戏的力度、甜蜜点或暗变量配置。
return {
    version = "sweep-demo-1",
    title = "舆论刹车",
    sweep = {
        unitsPerSecond = 0.75, -- 每秒移动的归一化距离；单程约 1.33 秒，可改后重新构建。
        initialPhase = 0.15,
    },
}
