-- 建筑大炮 prefab
-- 美术规则: 第一阶段使用原版月码海盗炮(boat_cannon)模型与音效, 不制作新美术
local assets =
{
    Asset("ANIM", "anim/boat_cannon.zip"),
}

local prefabs =
{
    "collapse_small",
    "gears",
}

-- 客户端: 收到开炮网络变量后生成本地炮弹飞行特效(服务器不逐帧移动炮弹)
local function OnFireDirty(inst)
    if TheWorld.ismastersim then
        return
    end
    local fx = SpawnPrefab("ccbp_shot")
    if fx == nil then
        return
    end
    local x, y, z = inst.Transform:GetWorldPosition()
    fx.cc_x0 = x
    fx.cc_z0 = z
    fx.cc_x1 = inst.fire_x:value()
    fx.cc_z1 = inst.fire_z:value()
    fx.cc_T = 0.9
    fx.cc_t = 0
    fx.Transform:SetPosition(x, 1.4, z)
end

local function DescribeCannon(inst, viewer)
    local comp = inst.components.constructioncannon
    if comp == nil then
        return "一门奇怪的炮"
    end
    return comp:GetStatusText()
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("boat_cannon")
    inst.AnimState:SetBuild("boat_cannon")
    inst.AnimState:PlayAnimation("idle", true)
    inst.AnimState:HideSymbol("cannon_flap_down")

    MakeObstaclePhysics(inst, 0.9)

    inst:AddTag("structure")
    inst:AddTag("construction_cannon")

    -- 网络同步变量(必须在 SetPristine 之前添加; vanilla 惯例传 inst.GUID)
    inst.net_state = net_byte(inst.GUID, "ccbp.state")
    inst.net_uid = net_string(inst.GUID, "ccbp.uid")
    inst.net_mats = net_string(inst.GUID, "ccbp.mats", "ccbpmatsdirty")
    inst.net_ready = net_bool(inst.GUID, "ccbp.ready", "ccbpreadydirty")
    inst.fire_x = net_float(inst.GUID, "ccbp.firex")
    inst.fire_z = net_float(inst.GUID, "ccbp.firez")
    inst.fire_seq = net_ushortint(inst.GUID, "ccbp.fireseq", "ccbpfire")

    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        inst:ListenForEvent("ccbpfire", OnFireDirty)
        -- [诊断] 客户端replica的mod组件动作同步通道
        if inst.actionreplica ~= nil and inst.actionreplica.modactioncomponents ~= nil then
            local names = {}
            for k, v in pairs(inst.actionreplica.modactioncomponents) do
                table.insert(names, k)
            end
            print("[CCBP][诊断] 客户端replica mod动作通道: " .. table.concat(names, ", "))
        else
            print("[CCBP][诊断] 客户端replica mod动作通道: 无")
        end
        return inst
    end

    inst:AddComponent("inspectable")
    inst.components.inspectable.descriptionfn = DescribeCannon

    -- 货舱(放施工材料), UI 参数在 modmain 里通过 containers.params 注册
    inst:AddComponent("container")
    inst.components.container:WidgetSetup("ccbp_cannon")

    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot({ "gears" })

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnFinishCallback(function(inst, worker)
        local fx = SpawnPrefab("collapse_small")
        if fx ~= nil then
            local x, y, z = inst.Transform:GetWorldPosition()
            fx.Transform:SetPosition(x, y, z)
        end
        inst.components.lootdropper:DropLoot(Vector3(inst.Transform:GetWorldPosition()))
        inst:Remove()
    end)

    -- 大炮会说话(播报施工状态)
    inst:AddComponent("talker")
    inst.components.talker.fontsize = 35
    inst.components.talker.font = TALKINGFONT
    inst.components.talker.offset = Vector3(0, -400, 0)

    inst:AddComponent("constructioncannon")

    -- 原版网络同步的实体右键动作: 绕开 mod 组件动作同步通道, 保证右键一定能打开蓝图库
    inst:SetInherentSceneAltAction(ACTIONS.CCBP_BROWSE)

    -- [诊断] 服务器mod名单与本实体的mod组件动作注册状态(每次生成大炮仅一次)
    local servermods = ModManager:GetServerModsNames()
    print("[CCBP][诊断] 服务器mod名单: " .. (servermods ~= nil and table.concat(servermods, ", ") or "nil"))
    if inst.modactioncomponents ~= nil then
        for modname, ids in pairs(inst.modactioncomponents) do
            print("[CCBP][诊断] 实体mod组件动作: " .. modname .. " -> " .. table.concat(ids, ","))
        end
    else
        print("[CCBP][诊断] 实体mod组件动作: 未注册")
    end

    return inst
end

return Prefab("construction_cannon", fn, assets, prefabs),
    MakePlacer("construction_cannon_placer", "boat_cannon", "boat_cannon", "idle")
