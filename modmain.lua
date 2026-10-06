----------------------------------------------------------------
-- DST Construction Cannon 建筑大炮
-- modmain 只负责注册: prefab / 组件 / 动作 / RPC / 配方 / 选项注入
-- 全部游戏逻辑在 scripts/ccbp_*.lua 与 scripts/components/ 中
----------------------------------------------------------------
local require = GLOBAL.require

local CCBP = require "ccbp_config"
CCBP.ApplyModOptions(GetModConfigData)
CCBP.MOD_BP_DIR = MODROOT .. "blueprints/"

PrefabFiles = {
    "construction_cannon",
    "projection_blueprint",
    "ccbp_fx",
}

-- ===== 字符串 =====
local STRINGS = GLOBAL.STRINGS
STRINGS.NAMES.CONSTRUCTION_CANNON = "建筑大炮"
STRINGS.RECIPE_DESC.CONSTRUCTION_CANNON =
    "读取蓝图库并自动施工。\n右键打开蓝图库; 施工材料放进货舱或附近箱子。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.CONSTRUCTION_CANNON = "一门能自己盖房子的大炮!"
STRINGS.NAMES.PROJECTION_BLUEPRINT = "建筑蓝图"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.PROJECTION_BLUEPRINT = "记录着建筑布局的蓝图, 右键放置投影。"

-- ===== 大炮货舱 UI(官方 containers.params 机制, 3x3 箱子界面) =====
local containers = require("containers")
containers.params.ccbp_cannon = {
    widget = {
        slotpos = {},
        animbank = "ui_chest_3x3",
        animbuild = "ui_chest_3x3",
        pos = GLOBAL.Vector3(0, 200, 0),
        side_align_tip = 160,
    },
    type = "chest",
}
for y = 2, 0, -1 do
    for x = 0, 2 do
        table.insert(containers.params.ccbp_cannon.widget.slotpos,
            GLOBAL.Vector3(80 * x - 80 * 2 + 80, 80 * y - 80 * 2 + 80, 0))
    end
end

-- ===== 组件 =====
-- 注意: mod 组件不需要注册, inst:AddComponent 时按路径 require(scripts/components/) 自动加载
-- "named" 组件原版已在 REPLICATABLE_COMPONENTS 中, 无需再注册

-- ===== 动作 =====
local Actions = require "ccbp_actions"
AddAction("CCBP_PLACE", "放置投影", Actions.OnPlace)
AddAction("CCBP_BROWSE", "蓝图库", Actions.OnBrowse)
AddAction("CCBP_CANCEL", "取消施工", Actions.OnCancel)
-- 施工中"取消施工"要压过"蓝图库"(两者都在右键列表里)
-- 注意: modmain 环境没有 __index 兜底, 游戏全局必须用 GLOBAL.* 访问
GLOBAL.ACTIONS.CCBP_CANCEL.priority = 1
AddComponentAction("SCENE", "constructioncannon", Actions.SceneCannon)
AddComponentAction("INVENTORY", "construction_blueprint", Actions.InventoryBlueprint)

-- ===== RPC(两侧注册顺序必须一致, 保证 id 对应) =====
local NetData = require "ccbp_netdata"
local RPC = require "ccbp_rpc"

-- 客户端 → 服务器
AddModRPCHandler(CCBP.MOD_NS, "RequestList", RPC.RequestList)
AddModRPCHandler(CCBP.MOD_NS, "RequestBlueprintData", RPC.RequestBlueprintData)
AddModRPCHandler(CCBP.MOD_NS, "BurnBlueprint", RPC.BurnBlueprint)
AddModRPCHandler(CCBP.MOD_NS, "ConfirmConstruction", RPC.ConfirmConstruction)
AddModRPCHandler(CCBP.MOD_NS, "CancelConstruction", RPC.CancelConstruction)
AddModRPCHandler(CCBP.MOD_NS, "LoadBlueprintFile", RPC.LoadBlueprintFile)
AddModRPCHandler(CCBP.MOD_NS, "ReloadStore", RPC.ReloadStore)

-- 客户端系统(在专用服务器上只注册不执行)
local Placement = require "ccbp_placement"
local UI = require "ccbp_uiscreens"
UI.SetPlacementRef(Placement)
NetData.on_blueprint = Placement.OnBlueprintData
NetData.on_list = UI.OnList

-- 服务器 → 客户端
AddClientModRPCHandler(CCBP.MOD_NS, "BPData", NetData.OnBlueprintChunk)
AddClientModRPCHandler(CCBP.MOD_NS, "ListData", NetData.OnListChunk)
AddClientModRPCHandler(CCBP.MOD_NS, "Toast", UI.OnToast)
AddClientModRPCHandler(CCBP.MOD_NS, "StartPlacement", Placement.OnStartPlacement)
AddClientModRPCHandler(CCBP.MOD_NS, "OpenBrowser", UI.OnOpenBrowser)

-- ===== 配方 =====
AddRecipe2("construction_cannon",
    {
        GLOBAL.Ingredient("gears", 2),
        GLOBAL.Ingredient("boards", 2),
        GLOBAL.Ingredient("cutstone", 4),
    },
    GLOBAL.TECH.SCIENCE_TWO,
    { placer = "construction_cannon_placer", image = "boat_cannon_kit.tex", min_spacing = 2 },
    { "STRUCTURES" })

-- ===== 世界加载时挂载蓝图库(仅服务器) =====
AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end
    inst:AddComponent("ccbp_store")
end)

-- ===== 确认模式输入拦截(两端注册, 运行时只对本地玩家生效) =====
AddComponentPostInit("playercontroller", function(comp, inst)
    local oldOnControl = comp.OnControl
    comp.OnControl = function(self, control, down)
        -- 闭包运行在 modmain 环境, ThePlayer 必须经 GLOBAL 访问
        if self.inst ~= nil and self.inst == GLOBAL.ThePlayer and Placement.IsControlBlocked(control) then
            return
        end
        return oldOnControl(self, control, down)
    end
end)

-- ===== [诊断] 右键大炮时打印实际生成的动作列表(2秒节流) =====
AddComponentPostInit("playeractionpicker", function(comp, inst)
    local oldGetSceneActions = comp.GetSceneActions
    if oldGetSceneActions == nil then
        return
    end
    local last_t = 0
    comp.GetSceneActions = function(self, useitem, right)
        local acts = oldGetSceneActions(self, useitem, right)
        if right and useitem ~= nil and useitem:IsValid() and useitem:HasTag("construction_cannon") then
            local now = GLOBAL.GetTime()
            if now - last_t > 2 then
                last_t = now
                local names = {}
                for _, ba in ipairs(acts) do
                    table.insert(names, tostring(ba.action ~= nil and ba.action.id or "?"))
                end
                print("[CCBP][诊断] 右键大炮动作列表: [" .. table.concat(names, ",")
                    .. "] inherent动作=" .. tostring(useitem.inherentscenealtaction ~= nil))
            end
        end
        return acts
    end
end)

-- ===== 调试 =====
if CCBP.DEBUG then
    require "ccbp_debug"
end
