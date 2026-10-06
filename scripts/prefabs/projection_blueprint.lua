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
