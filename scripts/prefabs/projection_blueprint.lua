-- 建筑蓝图物品
-- 只保存 blueprint_id(完整建筑数据在服务器的 ccbp_store), 显示名通过 named 组件同步
local assets =
{
    Asset("ANIM", "anim/papyrus.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("papyrus")
    inst.AnimState:SetBuild("papyrus")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("ccbp_blueprint")
    inst:AddTag("_named")

    inst.net_bpid = net_string(inst.GUID, "ccbp.bpid")
    -- 已确认的投影位置(服务器写, 客户端拿取蓝图时读取以还原投影)
    inst.net_plc = net_bool(inst.GUID, "ccbp.plc")
    inst.net_plcx = net_float(inst.GUID, "ccbp.plcx")
    inst.net_plcz = net_float(inst.GUID, "ccbp.plcz")
    inst.net_plcq = net_byte(inst.GUID, "ccbp.plcq")

    MakeInventoryFloatable(inst, "med", nil, 0.75)

    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("papyrus")
    inst.components.inventoryitem:SetSinks(true)

    inst:AddComponent("inspectable")

    inst:AddComponent("named")

    inst:AddComponent("construction_blueprint")

    return inst
end

return Prefab("projection_blueprint", fn, assets)
