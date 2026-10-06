-- DST Construction Cannon 建筑大炮
-- 独立实现 Base Projection JSON 蓝图的自动施工系统(类似 Create Schematicannon)
name = "建筑大炮 Construction Cannon"
description = [[读取 Base Projection 格式的 JSON 蓝图,用建筑大炮自动施工!

流程: 蓝图JSON → 莎草纸刻录蓝图 → 拿起蓝图放置投影 → WASD微调/QE旋转 → 确认施工 → 大炮自动建造

蓝图文件放入游戏根目录 unsafedata/ 或本mod目录 blueprints/
蓝图JSON格式与 Base Projection 兼容(顶层 x,y,z,name,data)。]]
author = "VibeCoding"
version = "0.1.0"

api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

all_clients_require_mod = true
client_only_mod = false
server_only_mod = false

server_filter_tags = { "construction", "blueprint" }

configuration_options =
{
    {
        name = "ccbp_interval",
        label = "建造间隔",
        hover = "大炮每发炮弹之间的间隔",
        options =
        {
            { description = "快 (0.75秒)", data = 0.75 },
            { description = "标准 (1.5秒)", data = 1.5 },
            { description = "慢 (2.5秒)", data = 2.5 },
            { description = "很慢 (4秒)", data = 4 },
        },
        default = 1.5,
    },
    {
        name = "ccbp_range",
        label = "施工范围",
        hover = "投影中心与建筑大炮的最大距离",
        options =
        {
            { description = "近 (30)", data = 30 },
            { description = "标准 (60)", data = 60 },
            { description = "远 (120)", data = 120 },
        },
        default = 60,
    },
    {
        name = "ccbp_matradius",
        label = "取料范围",
        hover = "大炮自动从附近箱子取材料的半径, 0=只用大炮货舱",
        options =
        {
            { description = "仅大炮货舱", data = 0 },
            { description = "小 (6)", data = 6 },
            { description = "标准 (12)", data = 12 },
            { description = "大 (24)", data = 24 },
        },
        default = 6,
    },
    {
        name = "ccbp_debug",
        label = "调试命令",
        hover = "启用 c_ccbp_* 系列控制台命令",
        options =
        {
            { description = "关闭", data = false },
            { description = "开启", data = true },
        },
        default = false,
    },
}
