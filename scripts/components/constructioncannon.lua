-- 建筑大炮组件(仅服务器): 施工队列状态机
-- 状态: IDLE / CHECKING / WAITING_MATERIAL / BUILDING / COMPLETED / ERROR
-- 服务器只在开炮瞬间设置网络变量, 炮弹飞行由客户端本地特效表现, 落地生成由服务器延时执行
local CCBP = require "ccbp_config"

-- 大炮实例注册表(按uid): 必须是独立的文件级 local——
-- 构造函数闭包在 local ConstructionCannon 声明完成前编译, 闭包里引用不到类本身(strict.lua 会报未声明全局)
local ByUID = {}

local ConstructionCannon = Class(function(self, inst)
    self.inst = inst
    self.state = "IDLE"
    self.job = nil
    self.fire_cd = 0
    self.ticker = nil
    self.uid = tostring(inst.GUID)
    if inst.net_uid ~= nil then
        inst.net_uid:set(self.uid)
    end
    ByUID[self.uid] = self
    self.inst:ListenForEvent("onremove", function()
        ByUID[self.uid] = nil
    end)
end)

function ConstructionCannon.GetByUID(uid)
    if uid == nil then
        return nil
    end
    return ByUID[tostring(uid)]
end

function ConstructionCannon:GetUID()
    return self.uid
end

function ConstructionCannon:SetState(s)
    self.state = s
    if self.inst.net_state ~= nil then
        self.inst.net_state:set(CCBP.STATE[s] or 0)
    end
end

function ConstructionCannon:Say(msg)
    if self.inst.components.talker ~= nil then
        self.inst.components.talker:Say(msg)
    end
end

-- ==================== 材料系统 ====================

-- prefab -> (recipe, 每次配方产出数量)
local function ResolveRecipe(prefab)
    local r = AllRecipes[prefab]
    if r ~= nil and r.ingredients ~= nil and #r.ingredients > 0 then
        return r, 1
    end
    r = AllRecipes[prefab .. "_item"]
    if r ~= nil and r.ingredients ~= nil and #r.ingredients > 0 then
        return r, r.numtogive or 1
    end
    if string.sub(prefab, 1, 6) == "fence_" then
        local kit = (prefab == "fence_gate") and "fence_gate_item" or "fence_item"
        r = AllRecipes[kit]
        if r ~= nil and r.ingredients ~= nil and #r.ingredients > 0 then
            return r, r.numtogive or 1
        end
    end
    return nil, 1
end

-- 材料来源: 大炮货舱 + 取料范围内的箱子("_container" 是引擎为 container 组件自动加的tag)
local function IterContainers(inst)
    local list = {}
    if CCBP.MATERIAL_RADIUS > 0 then
        local x, y, z = inst.Transform:GetWorldPosition()
        local ents = TheSim:FindEntities(x, y, z, CCBP.MATERIAL_RADIUS, { "_container" })
        for _, ent in ipairs(ents) do
            if ent ~= inst and ent.components ~= nil and ent.components.container ~= nil then
                list[#list + 1] = ent.components.container
            end
        end
    end
    if inst.components.container ~= nil then
        list[#list + 1] = inst.components.container
    end
    return list
end

local function CountInContainer(container, prefab)
    local n = 0
    for _, item in ipairs(container.slots or {}) do
        if item ~= nil and item.prefab == prefab then
            if item.components.stackable ~= nil then
                n = n + item.components.stackable:StackSize()
            else
                n = n + 1
            end
        end
    end
    return n
end

local function TakeFromContainer(container, prefab, want)
    local taken = 0
    local slots = container.slots
    if slots == nil then
        return 0
    end
    for i = 1, #slots do
        if taken >= want then
            break
        end
        local item = container.slots[i]
        if item ~= nil and item.prefab == prefab then
            if item.components.stackable ~= nil then
                local avail = item.components.stackable:StackSize()
                local take = math.min(avail, want - taken)
                if take >= avail then
                    container:RemoveItem(item, true)
                    item:Remove()
                else
                    local got = item.components.stackable:Get(take)
                    if got ~= nil then
                        got:Remove()
                    end
                end
                taken = taken + take
            else
                container:RemoveItem(item, true)
                item:Remove()
                taken = taken + 1
            end
        end
    end
    return taken
end

-- 计算单步材料需求(把 *_item 配方按产出数量分摊, 小数部分累积到 cost_acc)
-- 返回 needs(整数需求列表), updates(累积器更新值); 无配方返回 nil(免费)
local function ComputeNeeds(self, s)
    local recipe, per = ResolveRecipe(s.prefab)
    if recipe == nil then
        return nil, nil
    end
    local updates, needs = {}, {}
    for _, ing in ipairs(recipe.ingredients) do
        if ing ~= nil and ing.type ~= nil and (ing.amount or 0) > 0 then
            local acc = (updates[ing.type] or self.job.cost_acc[ing.type] or 0) + ing.amount / per
            local whole = math.floor(acc + 0.000001)
            updates[ing.type] = acc - whole
            if whole > 0 then
                needs[#needs + 1] = { type = ing.type, count = whole }
            end
        end
    end
    return needs, updates
end

local function AvailableCount(self, item_type)
    local n = 0
    for _, container in ipairs(IterContainers(self.inst)) do
        n = n + CountInContainer(container, item_type)
    end
    return n
end

function ConstructionCannon:HasMaterials(s)
    local needs = (ComputeNeeds(self, s))
    if needs == nil then
        return true
    end
    for _, nd in ipairs(needs) do
        if AvailableCount(self, nd.type) < nd.count then
            return false
        end
    end
    return true
end

function ConstructionCannon:TakeMaterials(s)
    local needs, updates = ComputeNeeds(self, s)
    if needs == nil then
        return true
    end
    for _, nd in ipairs(needs) do
        local left = nd.count
        for _, container in ipairs(IterContainers(self.inst)) do
            if left <= 0 then
                break
            end
            left = left - TakeFromContainer(container, nd.type, left)
        end
        if left > 0 then
            return false
        end
    end
    for k, v in pairs(updates) do
        self.job.cost_acc[k] = v
    end
    return true
end

local function MissingText(self)
    local s = self.job ~= nil and self.job.steps[self.job.next] or nil
    if s == nil then
        return ""
    end
    local recipe, per = ResolveRecipe(s.prefab)
    if recipe == nil then
        return ""
    end
    local parts = {}
    for _, ing in ipairs(recipe.ingredients) do
        if ing ~= nil and ing.type ~= nil and (ing.amount or 0) > 0 then
            local need = math.ceil(ing.amount / per)
            local have = AvailableCount(self, ing.type)
            if have < need then
                local label = STRINGS.NAMES[string.upper(ing.type)] or ing.type
                parts[#parts + 1] = label .. "x" .. (need - have)
            end
        end
    end
    return table.concat(parts, ", ")
end

-- ==================== 步骤校验与执行 ====================

-- 单步合法性: 可站立地面 + 0.8单位内没有已存在的建筑
function ConstructionCannon:StepValid(s)
    if not TheWorld.Map:IsPassableAtPoint(s.x, 0, s.z) then
        return false
    end
    local ents = TheSim:FindEntities(s.x, 0, s.z, 0.8, { "structure" })
    if #ents > 0 then
        return false
    end
    return true
end

function ConstructionCannon:SpawnBuilding(s)
    local ent = SpawnPrefab(s.prefab)
    if ent == nil then
        return false
    end
    ent.Transform:SetPosition(s.x, 0, s.z)
    if s.rot ~= nil and (s.rot % 360) ~= 0 then
        ent.Transform:SetRotation(s.rot)
    end
    if s.scale ~= nil then
        ent.Transform:SetScale(s.scale[1], s.scale[2], s.scale[3])
    end
    local fx = SpawnPrefab("collapse_small")
    if fx ~= nil then
        fx.Transform:SetPosition(s.x, 0, s.z)
    end
    return true
end

-- 开炮: 服务器只做一次动画/音效/网络变量设置(不逐帧移动炮弹)
function ConstructionCannon:Fire(s)
    local inst = self.inst
    inst.AnimState:PlayAnimation("shoot")
    inst.AnimState:PushAnimation("idle", true)
    inst.SoundEmitter:PlaySound("monkeyisland/cannon/shoot")

    if inst.fire_x ~= nil and inst.fire_z ~= nil and inst.fire_seq ~= nil then
        inst.fire_x:set(s.x)
        inst.fire_z:set(s.z)
        inst.fire_seq:set((inst.fire_seq:value() + 1) % 65536)
    end

    -- 炮弹飞行时间内服务器不做事, 落地时刻再做一次合法性检查并生成建筑
    local job = self.job
    inst:DoTaskInTime(CCBP.FLIGHT_TIME, function()
        if self.job ~= job or self.inst == nil or not self.inst:IsValid() then
            return
        end
        if self:StepValid(s) and self:SpawnBuilding(s) then
            job.built = job.built + 1
        else
            job.skipped = job.skipped + 1
        end
    end)
end

-- ==================== 队列状态机 ====================

function ConstructionCannon:StartTicker()
    self:StopTicker()
    self.ticker = self.inst:DoPeriodicTask(0.5, function()
        self:OnTick()
    end, 0.1)
end

function ConstructionCannon:StopTicker()
    if self.ticker ~= nil then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function ConstructionCannon:OnTick()
    if self.job == nil then
        self:StopTicker()
        return
    end
    self.fire_cd = (self.fire_cd or 0) - 0.5

    if self.state == "CHECKING" then
        self:SetState("BUILDING")
    end

    if self.state == "BUILDING" or self.state == "WAITING_MATERIAL" then
        self:BuildingTick()
    end
end

function ConstructionCannon:BuildingTick()
    local job = self.job
    local waiting = (self.state == "WAITING_MATERIAL")

    -- 先跳过所有非法位置
    local guard = 0
    while job.next <= #job.steps and guard < CCBP.MAX_STEPS_PER_TICK do
        guard = guard + 1
        local s = job.steps[job.next]
        if self:StepValid(s) then
            break
        end
        job.skipped = job.skipped + 1
        job.next = job.next + 1
    end
    if job.next > #job.steps then
        self:Finish()
        return
    end

    if self.fire_cd > 0 then
        return
    end

    local s = job.steps[job.next]
    if self:HasMaterials(s) then
        if self:TakeMaterials(s) then
            self:SetState("BUILDING")
            self.fire_cd = CCBP.BUILD_INTERVAL
            self:Fire(s)
            job.next = job.next + 1
        else
            self:SetState("WAITING_MATERIAL")
        end
    elseif not waiting then
        self:SetState("WAITING_MATERIAL")
        local mt = MissingText(self)
        self:Say(mt ~= "" and ("等待材料: " .. mt) or "等待材料… 请把材料放进大炮货舱或附近箱子")
    end
end

function ConstructionCannon:Finish()
    local job = self.job
    self.job = nil
    self:SetState("COMPLETED")
    self:Say(string.format("施工完成: 成功%d个, 跳过%d个", job.built or 0, job.skipped or 0))
    self.inst:DoTaskInTime(8, function()
        if self.state == "COMPLETED" and self.job == nil then
            self:SetState("IDLE")
        end
    end)
end

function ConstructionCannon:Enqueue(steps, bpname)
    if self.job ~= nil then
        return false, "大炮正在施工中(可右键取消当前任务)"
    end
    if steps == nil or #steps <= 0 then
        return false, "没有可施工的结构"
    end
    self.job = { steps = steps, next = 1, built = 0, skipped = 0, cost_acc = {} }
    self.fire_cd = 0
    self:SetState("CHECKING")
    self:Say("开始施工: " .. tostring(bpname or "蓝图") .. " (" .. #steps .. "个结构)")
    self:StartTicker()
    return true
end

function ConstructionCannon:Cancel()
    if self.job ~= nil then
        self.job = nil
        self:SetState("IDLE")
        self:StopTicker()
        self:Say("施工已取消")
    end
end

function ConstructionCannon:GetStatusText()
    local store = TheWorld ~= nil and TheWorld.components.ccbp_store or nil
    local loaded = store ~= nil and store:Count() or 0
    if self.state == "IDLE" then
        return string.format("建筑大炮(就绪)\n已加载蓝图: %d张\n右键打开蓝图库\n施工材料放进货舱或附近箱子", loaded)
    elseif self.state == "CHECKING" then
        return "正在准备施工…"
    elseif self.state == "BUILDING" then
        local j = self.job
        return string.format("施工中: %d/%d (跳过%d)",
            j ~= nil and (j.next - 1) or 0, j ~= nil and #j.steps or 0, j ~= nil and j.skipped or 0)
    elseif self.state == "WAITING_MATERIAL" then
        return "等待材料… 请把材料放进大炮货舱或附近箱子"
    elseif self.state == "COMPLETED" then
        return "施工完成!"
    elseif self.state == "ERROR" then
        return "施工出错"
    end
    return nil
end

function ConstructionCannon:OnSave()
    return {}
end

function ConstructionCannon:OnLoad()
    -- 施工队列不持久化: 载入后回到 IDLE
    self.job = nil
    self.state = "IDLE"
end

return ConstructionCannon
