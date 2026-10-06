-- 客户端投影(ghost)系统
-- 用"客户端方式"生成真实 prefab 作为半透明 ghost:
--   临时把 TheWorld.ismastersim 置为 false 再 SpawnPrefab(主机上也如此),
--   然后去物理/去SG/去AI/去声音, 染色为半透明绿色(参考 Base Projection 的成熟做法)
local CCBP = require "ccbp_config"
local TransformCC = require "ccbp_transform"

local Ghosts = {
    list = {}, -- { ent, prefab, dx, dz, rot, scale, fence }
    failed = 0,
}

local function ClientSpawn(prefab)
    local _m = TheWorld.ismastersim
    TheWorld.ismastersim = false
    local ok, ent = pcall(SpawnPrefab, prefab)
    TheWorld.ismastersim = _m
    if ok then
        return ent
    end
    return nil
end

local function ClientRemove(ent)
    local _m = TheWorld.ismastersim
    TheWorld.ismastersim = false
    pcall(ent.Remove, ent)
    TheWorld.ismastersim = _m
end

-- 栅栏类: 按最终朝向的 45° 扇区在 thin/wide bank 之间切换(Base Projection 同款修复)
local function FenceBankFor(prefab, rot)
    local rot_enum = math.floor((math.floor(rot + 0.5) / 45) % 8)
    if rot_enum % 2 == 0 then
        return (prefab == "fence_junk") and "fence_thin_junk" or (prefab .. "_thin")
    end
    return prefab
end

local function SetupProxy(ent, st)
    if ent == nil or not ent:IsValid() then
        return false
    end

    if ent.CancelAllPendingTasks ~= nil then
        ent:CancelAllPendingTasks()
    end
    ent.OnEntityWake = nil
    ent.OnEntitySleep = nil
    if ent.ClearStateGraph ~= nil then
        ent:ClearStateGraph()
    end
    if ent.SetBrain ~= nil then
        pcall(ent.SetBrain, ent, nil)
    end
    if ent.SoundEmitter ~= nil then
        ent.SoundEmitter:KillAllSounds()
    end
    if ent.Physics ~= nil then
        pcall(function()
            ent.Physics:SetActive(false)
        end)
    end
    if ent.Light ~= nil then
        ent.Light:Enable(false)
    end
    if ent.MiniMapEntity ~= nil then
        pcall(function()
            ent.MiniMapEntity:SetEnabled(false)
        end)
    end

    ent:RemoveTag("iswet")
    ent:RemoveTag("wet")
    ent:AddTag("FX")
    ent:AddTag("NOCLICK")
    ent:AddTag("CLASSIFIED")
    ent.persists = false

    if ent.AnimState ~= nil then
        ent.AnimState:SetMultColour(0, 1, 0, 0.8)

        if ent:HasTag("fence") then
            local bank, build, anim = st.bank, st.build, st.anim
            if build == nil or build == "" then
                build = st.prefab
                if st.prefab == "fence_junk" then
                    build = "fence_junk_build"
                end
            end
            if anim == nil or anim == "" then
                anim = "idle"
            end
            local rot = (st.rot or 0) % 360
            bank = FenceBankFor(st.prefab, rot)
            if build ~= nil and build ~= "" then
                ent.AnimState:SetBuild(build)
            end
            if bank ~= nil and bank ~= "" then
                ent.AnimState:SetBank(bank)
            end
            ent.AnimState:PlayAnimation(anim)
        elseif st.anim ~= nil and st.anim ~= "" then
            if st.build ~= nil and st.build ~= "" then
                ent.AnimState:SetBuild(st.build)
            end
            if st.bank ~= nil and st.bank ~= "" then
                ent.AnimState:SetBank(st.bank)
            end
            ent.AnimState:PlayAnimation(st.anim)
        end

        -- layer 5 是 onground 类放置物(地皮/路径), 需要压平显示
        if st.layer == 5 then
            ent.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
            ent.AnimState:SetLayer(5)
            ent.AnimState:SetSortOrder(5)
        end
    end
    return true
end

-- 为蓝图生成全部 ghost, 返回(成功数, 失败数)
function Ghosts.SpawnFor(bp)
    Ghosts.Clear()
    Ghosts.failed = 0
    for _, st in ipairs(bp.structures) do
        local ent = ClientSpawn(st.prefab)
        if ent == nil or not SetupProxy(ent, st) then
            if ent ~= nil then
                ClientRemove(ent)
            end
            Ghosts.failed = Ghosts.failed + 1
        else
            Ghosts.list[#Ghosts.list + 1] = {
                ent = ent,
                prefab = st.prefab,
                dx = st.x,
                dz = st.z,
                rot = st.rot or 0,
                scale = st.scale,
                fence = ent:HasTag("fence"),
            }
        end
    end
    return #Ghosts.list, Ghosts.failed
end

-- 把全部 ghost 变换到放置原点 + 旋转 q
function Ghosts.Apply(ox, oz, q, q_changed)
    local angle = (math.floor(q) % 4) * 90
    for _, g in ipairs(Ghosts.list) do
        if g.ent:IsValid() then
            local dx, dz = TransformCC.RotateOffset(g.dx, g.dz, angle)
            local rot = (g.rot + angle) % 360
            g.ent.Transform:SetPosition(ox + dx, 0, oz + dz)
            g.ent.Transform:SetRotation(rot)
            if g.scale ~= nil then
                g.ent.Transform:SetScale(g.scale[1], g.scale[2], g.scale[3])
            end
            if q_changed and g.fence and g.ent.AnimState ~= nil then
                g.ent.AnimState:SetBank(FenceBankFor(g.prefab, rot))
            end
        end
    end
end

function Ghosts.Clear()
    for _, g in ipairs(Ghosts.list) do
        if g.ent ~= nil and g.ent:IsValid() then
            ClientRemove(g.ent)
        end
    end
    Ghosts.list = {}
end

function Ghosts.GetFailed()
    return Ghosts.failed
end

return Ghosts
