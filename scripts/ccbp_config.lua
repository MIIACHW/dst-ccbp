-- 全局配置与常量(所有端共享)
-- 模块名统一使用 ccbp_ 前缀, 由 modmain 统一 require 进 package.loaded
local CCBP = {
    MOD_NS = "CCBP",

    -- 蓝图来源
    JSON_DIR = "unsafedata/",       -- Base Projection 约定目录(游戏根目录下, io.open 相对路径)
    MOD_BP_DIR = "",                -- 本MOD目录下 blueprints/, 由 modmain 填充
    INDEX_FILE = "ccbp_index.json", -- 可选索引文件: ["a.json", "b.json"]
    MAX_BLUEPRINTS = 200,
    MAX_STRUCTS = 1500,

    -- 施工参数(可被 mod 选项覆盖)
    BUILD_INTERVAL = 1.5,  -- 每发炮弹间隔(秒)
    CANNON_RANGE = 60,     -- 投影中心与大炮的最大距离
    MATERIAL_RADIUS = 6,   -- 自动取料半径(0=仅大炮货舱)
    FLIGHT_TIME = 0.9,     -- 炮弹飞行时间(秒), 服务器延时后落地生成建筑
    MAX_STEPS_PER_TICK = 20,

    -- 投影操作
    SNAP = 0.5,               -- 鼠标放置时原点吸附(世界单位)
    CONFIRM_SPEED = 10,       -- WASD 微调速度(单位/秒)
    CONFIRM_SPEED_SLOW = 2.5, -- 按住 Shift 的慢速微调
    LOAD_TIMEOUT = 10,        -- 蓝图数据传输超时(秒)

    -- 网络: 服务器→客户端 分块发送, 每 tick 最多发送块数
    DATA_CHUNKS_PER_TICK = 4,

    -- 客户端放置状态机
    MODE = { INACTIVE = 0, LOADING = 1, PLACING = 2, CONFIRMING = 3 },

    -- 施工队列状态(与规格一致, 同步为 net byte)
    STATE = {
        IDLE = 0,
        CHECKING = 1,
        WAITING_MATERIAL = 2,
        BUILDING = 3,
        COMPLETED = 4,
        ERROR = 5,
    },

    DEBUG = false,
}

function CCBP.ApplyModOptions(get)
    if get == nil then return end
    local v
    v = get("ccbp_interval")
    if type(v) == "number" then CCBP.BUILD_INTERVAL = v end
    v = get("ccbp_range")
    if type(v) == "number" then CCBP.CANNON_RANGE = v end
    v = get("ccbp_matradius")
    if type(v) == "number" then CCBP.MATERIAL_RADIUS = v end
    v = get("ccbp_debug")
    if type(v) == "boolean" then CCBP.DEBUG = v end
end

return CCBP
