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
    "读取蓝图库并自动施工。\n右键打开蓝图库; 施工材料放进大炮附近的箱子。"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.CONSTRUCTION_CANNON = "一门能自己盖房子的大炮!"
STRINGS.NAMES.PROJECTION_BLUEPRINT = "建筑蓝图"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.PROJECTION_BLUEPRINT = "记录着建筑布局的蓝图, 右键放置投影。"

-- ===== 大炮货槽 UI(官方 containers.params 机制) =====
-- 大炮只有 1 个蓝图专用槽; 施工材料全部从大炮周围容器读取(半径见模组选项"取料范围")
containers.params.ccbp_cannon = {
    widget = {
        slotpos = { GLOBAL.Vector3(-180, 40, 0) },
        pos = GLOBAL.Vector3(0, 222, 0),
        side_align_tip = 160,
    },
    type = "chest",
}
-- 蓝图槽只收蓝图
containers.params.ccbp_cannon.itemtestfn = function(container, item, slot)
    if item == nil or not item:IsValid() then
        return false
    end
    return item:HasTag("ccbp_blueprint")
end

-- ===== 组件 =====
-- 注意: mod 组件不需要注册, inst:AddComponent 时按路径 require(scripts/components/) 自动加载
-- "named" 组件原版已在 REPLICATABLE_COMPONENTS 中, 无需再注册

-- ===== 动作 =====
local Actions = require "ccbp_actions"
AddAction("CCBP_BROWSE", "蓝图库", Actions.OnBrowse)
AddAction("CCBP_CANCEL", "取消施工", Actions.OnCancel)
-- 施工中"取消施工"要压过"蓝图库"(两者都在右键列表里)
-- 注意: modmain 环境没有 __index 兜底, 游戏全局必须用 GLOBAL.* 访问
GLOBAL.ACTIONS.CCBP_CANCEL.priority = 1
-- 蓝图库是"即时动作"(打开界面, 不需要走近目标再执行):
-- instant 让 locomotor 直接入队执行, 跳过寻路到位流程
GLOBAL.ACTIONS.CCBP_BROWSE.instant = true
AddComponentAction("SCENE", "constructioncannon", Actions.SceneCannon)

-- ===== RPC(两侧注册顺序必须一致, 保证 id 对应) =====
local NetData = require "ccbp_netdata"
local RPC = require "ccbp_rpc"

-- 客户端 → 服务器
AddModRPCHandler(CCBP.MOD_NS, "RequestList", RPC.RequestList)
AddModRPCHandler(CCBP.MOD_NS, "RequestBlueprintData", RPC.RequestBlueprintData)
AddModRPCHandler(CCBP.MOD_NS, "BurnBlueprint", RPC.BurnBlueprint)
AddModRPCHandler(CCBP.MOD_NS, "PlaceBlueprint", RPC.PlaceBlueprint)
AddModRPCHandler(CCBP.MOD_NS, "StartConstruction", RPC.StartConstruction)
AddModRPCHandler(CCBP.MOD_NS, "CancelConstruction", RPC.CancelConstruction)
AddModRPCHandler(CCBP.MOD_NS, "LoadBlueprintFile", RPC.LoadBlueprintFile)
AddModRPCHandler(CCBP.MOD_NS, "ReloadStore", RPC.ReloadStore)

-- 客户端系统(在专用服务器上只注册不执行)
local Placement = require "ccbp_placement"
local UI = require "ccbp_uiscreens"
NetData.on_blueprint = Placement.OnBlueprintData
NetData.on_list = UI.OnList

-- 服务器 → 客户端
AddClientModRPCHandler(CCBP.MOD_NS, "BPData", NetData.OnBlueprintChunk)
AddClientModRPCHandler(CCBP.MOD_NS, "ListData", NetData.OnListChunk)
AddClientModRPCHandler(CCBP.MOD_NS, "Toast", UI.OnToast)
AddClientModRPCHandler(CCBP.MOD_NS, "OpenBrowser", UI.OnOpenBrowser)

-- 货舱界面的"所需材料"面板(挂在容器界面右侧)
local ContainerUI = require "ccbp_containerui"
AddClassPostConstruct("widgets/containerwidget", ContainerUI.Install)

-- 手持蓝图监视: 蓝图拿到手上自动进入投影放置, 放回背包自动退出
AddPlayerPostInit(function(inst)
    if not GLOBAL.TheNet:IsDedicated() then
        inst:DoPeriodicTask(GLOBAL.FRAMES, function(inst)
            Placement.WatchActiveItem(inst)
        end)
    end
end)

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
    local last_rmb_diag = 0
    comp.OnControl = function(self, control, down)
        if self.inst ~= nil and self.inst == GLOBAL.ThePlayer
            and control == GLOBAL.CONTROL_SECONDARY and down then
            -- [诊断] 右键按下时的全部门禁状态(1.5秒节流)
            local now = GLOBAL.GetTime()
            if now - last_rmb_diag > 1.5 then
                last_rmb_diag = now
                local enabled, hudblock = self:IsEnabled()
                print(string.format(
                    "[CCBP][诊断] 右键按下: enabled=%s hudblock=%s paused=%s RMBaction=%s placer=%s",
                    tostring(enabled), tostring(hudblock), tostring(GLOBAL.IsPaused()),
                    tostring(self.RMBaction ~= nil and self.RMBaction.action ~= nil and self.RMBaction.action.id or "nil"),
                    tostring(self.placer_recipe ~= nil and self.placer_recipe.name or "nil")))
            end
        end
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

-- ===== [诊断] 右键执行链路: DoAction / PushAction / actionfailed =====
AddComponentPostInit("playercontroller", function(comp, inst)
    local oldDoAction = comp.DoAction
    if oldDoAction ~= nil then
        comp.DoAction = function(self, buffaction, spellbook)
            if self.inst == GLOBAL.ThePlayer and buffaction ~= nil
                and buffaction.action ~= nil and buffaction.action.id == "CCBP_BROWSE" then
                local cur = self.inst:GetBufferedAction()
                print(string.format(
                    "[CCBP][诊断] DoAction(CCBP_BROWSE): busy=%s 已缓存动作=%s target=%s locomotor=%s mastersim=%s",
                    tostring(self:IsBusy()),
                    tostring(cur ~= nil and cur.action ~= nil and cur.action.id or "nil"),
                    tostring(buffaction.target ~= nil and buffaction.target:IsValid() or "nil"),
                    tostring(self.locomotor ~= nil),
                    tostring(self.ismastersim)))
            end
            return oldDoAction(self, buffaction, spellbook)
        end
    end
end)

AddComponentPostInit("locomotor", function(comp, inst)
    local oldPushAction = comp.PushAction
    if oldPushAction ~= nil then
        comp.PushAction = function(self, bufferedaction, run, try_instant)
            if self.inst == GLOBAL.ThePlayer and bufferedaction ~= nil
                and bufferedaction.action ~= nil and bufferedaction.action.id == "CCBP_BROWSE" then
                local ok, reason = bufferedaction:TestForStart()
                print(string.format(
                    "[CCBP][诊断] PushAction(CCBP_BROWSE): TestForStart=%s inv=%s doer有效=%s target有效=%s 初始持有者=%s",
                    tostring(ok), tostring(bufferedaction.invobject),
                    tostring(bufferedaction.doer ~= nil and bufferedaction.doer:IsValid()),
                    tostring(bufferedaction.target ~= nil and bufferedaction.target:IsValid()),
                    tostring(bufferedaction.initialtargetowner)))
            end
            return oldPushAction(self, bufferedaction, run, try_instant)
        end
    end
end)

AddPlayerPostInit(function(player)
    player:ListenForEvent("actionfailed", function(p, data)
        local act = data ~= nil and data.action or nil
        if act ~= nil and act.action ~= nil then
            print("[CCBP][诊断] actionfailed: " .. tostring(act.action.id))
        end
    end)
end)

-- ===== 调试 =====
if CCBP.DEBUG then
    require "ccbp_debug"
end
