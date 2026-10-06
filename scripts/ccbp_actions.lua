-- 动作处理函数(逻辑在这里, 由 modmain 用 AddAction/AddComponentAction 注册)
-- Action fn 在服务器执行; ComponentAction 回调在客户端执行
local CCBP = require "ccbp_config"
local NetData = require "ccbp_netdata"

local Actions = {}

-- ========== 服务器端 Action 处理 ==========

local function GetHeldBlueprint(act)
    local item = act.invobject
    if item == nil or item.components.construction_blueprint == nil then
        return nil
    end
    if item.components.inventoryitem == nil or not item.components.inventoryitem:IsHeld() then
        return nil
    end
    return item
end

-- 拿起蓝图 → 放置投影(通知持有者的客户端进入放置模式)
Actions.OnPlace = function(act)
    if act == nil or act.doer == nil then
        return false
    end
    local item = GetHeldBlueprint(act)
    if item == nil then
        return false
    end
    local id = item.components.construction_blueprint:GetID()
    if id == nil then
        return false
    end
    if TheWorld.ismastersim then
        NetData.SendStartPlacement(act.doer, id)
    end
    return true
end

-- 右键大炮 → 打开蓝图库
Actions.OnBrowse = function(act)
    print("[CCBP] 服务器收到打开蓝图库动作")
    local cannon = act ~= nil and act.target or nil
    if cannon == nil or cannon.components.constructioncannon == nil then
        print("[CCBP] OnBrowse失败: 目标大炮无效")
        return false
    end
    if TheWorld.ismastersim then
        NetData.SendOpenBrowser(act.doer, cannon.components.constructioncannon:GetUID(),
            STRINGS.NAMES.CONSTRUCTION_CANNON or "建筑大炮")
    end
    return true
end

-- 右键大炮 → 取消当前施工
Actions.OnCancel = function(act)
    local cannon = act ~= nil and act.target or nil
    if cannon == nil or cannon.components.constructioncannon == nil then
        return false
    end
    if TheWorld.ismastersim then
        cannon.components.constructioncannon:Cancel()
    end
    return true
end

-- ========== 客户端 ComponentAction 回调 ==========

-- 指向大炮(右键): 施工中显示"取消施工", 再加"蓝图库"
Actions.SceneCannon = function(inst, doer, actions, right)
    if not right or not inst:HasTag("construction_cannon") then
        return
    end
    local st = inst.net_state ~= nil and inst.net_state:value() or CCBP.STATE.IDLE
    if st >= CCBP.STATE.CHECKING and st <= CCBP.STATE.BUILDING then
        table.insert(actions, ACTIONS.CCBP_CANCEL)
    end
    table.insert(actions, ACTIONS.CCBP_BROWSE)
end

-- 蓝图物品在背包中(右键): 放置投影
Actions.InventoryBlueprint = function(inst, doer, actions, right)
    if not right or not inst:HasTag("ccbp_blueprint") then
        return
    end
    table.insert(actions, ACTIONS.CCBP_PLACE)
end

return Actions
