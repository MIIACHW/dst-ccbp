-- 客户端专用特效: 炮弹飞行(纯本地实体, 无网络)
-- 使用原版 cannonball_rock 模型旋转动画; 落地时客户端本地播放 dirt_puff
-- 真正的建筑生成由服务器在飞行时间结束后执行(见 constructioncannon 组件)
local assets =
{
    Asset("ANIM", "anim/cannonball_rock.zip"),
}

local function FlyStep(inst)
    inst.cc_t = (inst.cc_t or 0) + FRAMES
    local T = inst.cc_T or 0.9
    local p = math.min(inst.cc_t / T, 1)
    local x = Lerp(inst.cc_x0 or 0, inst.cc_x1 or 0, p)
    local z = Lerp(inst.cc_z0 or 0, inst.cc_z1 or 0, p)
    local dx = (inst.cc_x1 or 0) - (inst.cc_x0 or 0)
    local dz = (inst.cc_z1 or 0) - (inst.cc_z0 or 0)
    local dist = math.sqrt(dx * dx + dz * dz)
    local h = math.min(math.max(dist * 0.25, 1), 5)
    local y = 1.2 + h * 4 * p * (1 - p)
    inst.Transform:SetPosition(x, y, z)

    if p >= 1 then
        local puff = SpawnPrefab("dirt_puff")
        if puff ~= nil then
            puff.Transform:SetPosition(x, 0, z)
        end
        inst:Remove()
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst.persists = false

    inst.AnimState:SetBank("cannonball_rock")
    inst.AnimState:SetBuild("cannonball_rock")
    inst.AnimState:PlayAnimation("spin_loop", true)

    return inst
end

return Prefab("ccbp_shot", fn, assets)
