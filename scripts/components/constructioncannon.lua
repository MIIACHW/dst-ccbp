-- 建筑大炮组件(仅服务器): 施工队列状态机
-- 状态: IDLE / CHECKING / WAITING_MATERIAL / BUILDING / COMPLETED / ERROR
-- 服务器只在开炮瞬间设置网络变量, 炮弹飞行由客户端本地特效表现, 落地生成由服务器延时执行
local CCBP = require "ccbp_config"
local TransformCC = require "ccbp_transform"

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
    -- 蓝图槽变化(第一格放入/取出蓝图) → 更新就绪状态
    self.inst:ListenForEvent("itemget", function()
        self:RefreshBlueprintSlot()
    end)
    self.inst:ListenForEvent("itemlose", function()
        self:RefreshBlueprintSlot()
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

-- 蓝图槽(第一格)状态: 放入"已确认投影位置"的蓝图后 net_ready=true
function ConstructionCannon:RefreshBlueprintSlot()
    local bp = nil
    local container = self.inst.components.container
    if container ~= nil and container.slots ~= nil then
        bp = container.slots[1]
    end
    local ready = false
    if bp ~= nil and bp:IsValid() and bp.components.construction_blueprint ~= nil then
        self.blueprint_item = bp
        self.blueprint_placement = bp.components.construction_blueprint:GetPlacement()
        ready = (self.blueprint_placement ~= nil)
    else
        self.blueprint_item = nil
        self.blueprint_placement = nil
    end
    if self.inst.net_ready ~= nil then
        self.inst.net_ready:set(ready)
    end
    if self.job == nil then
        self:UpdateMatsText()
    end
end

-- [开始施工]: 从蓝图槽中的蓝图读取已确认的投影位置并开始施工
function ConstructionCannon:TryStartFromBlueprint()
    if self.job ~= nil then
        return false, "大炮正在施工中"
    end
    self:RefreshBlueprintSlot()
    local bpitem = self.blueprint_item
    local placement = self.blueprint_placement
    if bpitem == nil or placement == nil then
        return false, "蓝图槽中没有已确认投影位置的蓝图"
    end
    local id = bpitem.components.construction_blueprint:GetID()
    local store = TheWorld ~= nil and TheWorld.components.ccbp_store or nil
    local bp = store ~= nil and store:Get(id) or nil
    if bp == nil then
        return false, "蓝图数据不存在或未加载"
    end
    local cx, cy, cz = self.inst.Transform:GetWorldPosition()
    local dx, dz = placement.x - cx, placement.z - cz
    local maxr = CCBP.CANNON_RANGE + 5
    if dx * dx + dz * dz > maxr * maxr then
        return false, "投影位置离大炮太远"
    end
    local steps = TransformCC.ComputeSteps(bp, placement.x, placement.z, placement.q)
    local ok, msg = self:Enqueue(steps, bp.name)
    return ok, msg
end

-- 更新货槽界面的"所需材料"面板(net_string 同步给客户端)
-- 施工不按蓝图顺序: 哪个建筑材料齐备就先造哪个
function ConstructionCannon:UpdateMatsText()
    local txt = ""
    if self.job ~= nil then
        local total = #self.job.steps
        local done = math.min(total - (self.job.remaining or 0), total)
        local head
        if self.state == "WAITING_MATERIAL" then
            head = string.format("等待材料… (%d/%d)", done, total)
        elseif self.state == "BUILDING" or self.state == "CHECKING" then
            head = string.format("施工中 %d/%d", done, total)
        else
            head = "准备施工"
        end
        txt = head
        if self.state == "WAITING_MATERIAL" then
            local parts = AggregateMissing(self)
            if #parts > 0 then
                local shown = {}
                for i, p in ipairs(parts) do
                    if i > 6 then
                        table.insert(shown, "…")
                        break
                    end
                    table.insert(shown, p)
                end
                txt = txt .. "\n还缺: " .. table.concat(shown, ", ")
            end
        end
        if self.job.mats_lines ~= nil and #self.job.mats_lines > 0 then
            txt = txt .. "\n----------\n整单所需:\n" .. table.concat(self.job.mats_lines, "\n")
        end
    elseif self.blueprint_placement ~= nil then
        txt = "蓝图已就绪\n点击[开始施工]"
    else
        txt = "放入蓝图开始施工"
    end
    -- net_string 容量保护
    if #txt > 400 then
        txt = string.sub(txt, 1, 397) .. "…"
    end
    if self.inst.net_mats ~= nil then
        self.inst.net_mats:set(txt)
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

-- 可用材料计数(带每 tick 缓存: BuildingTick 开始时清空, 同一 tick 内不重复扫描容器)
local function AvailableCount(self, item_type)
    local cache = self._avail_cache
    if cache ~= nil then
        local c = cache[item_type]
        if c ~= nil then
            return c
        end
    end
    local n = 0
    for _, container in ipairs(IterContainers(self.inst)) do
        n = n + CountInContainer(container, item_type)
    end
    if cache ~= nil then
        cache[item_type] = n
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

-- 汇总所有未完成步骤还缺的材料(面板/播报用), 返回排序后的 {label xN} 数组
local function AggregateMissing(self)
    local totals = {}
    for i, s in ipairs(self.job.steps) do
        if self.job.pending[i] then
            local recipe, per = ResolveRecipe(s.prefab)
            if recipe ~= nil then
                for _, ing in ipairs(recipe.ingredients) do
                    if ing ~= nil and ing.type ~= nil and (ing.amount or 0) > 0 then
                        totals[ing.type] = (totals[ing.type] or 0) + ing.amount / per
                    end
                end
            end
        end
    end
    local parts = {}
    for t, amt in pairs(totals) do
        local lack = math.ceil(amt - AvailableCount(self, t) - 0.000001)
        if lack > 0 then
            local label = STRINGS.NAMES[string.upper(t)] or t
            parts[#parts + 1] = label .. " x" .. lack
        end
    end
    table.sort(parts)
    return parts
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
    print(string.format("[CCBP] 开炮: %s @ (%.1f, %.1f)", s.prefab, s.x, s.z))
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
    -- 注意: 用 job.cancelled 而不是 self.job 判断——队列收尾(Finish)不会取消已在飞行中的最后一炮
    local job = self.job
    inst:DoTaskInTime(CCBP.FLIGHT_TIME, function()
        if job.cancelled or self.inst == nil or not self.inst:IsValid() then
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
    self._avail_cache = {} -- 材料计数缓存: 每 tick 重建(玩家随时可能补料)

    -- 材料够了就先造: 扫描全部未完成步骤
    --   位置无效(被占/水面) → 跳过; 材料齐 → 立即开炮; 都不齐 → 等待
    for i, s in ipairs(job.steps) do
        if job.pending[i] and not self:StepValid(s) then
            if (job.skip_prints or 0) < 10 then
                print(string.format("[CCBP] 跳过无效位置: %s @ (%.1f, %.1f)", s.prefab, s.x, s.z))
                job.skip_prints = (job.skip_prints or 0) + 1
            end
            job.pending[i] = nil
            job.remaining = job.remaining - 1
            job.skipped = job.skipped + 1
        end
    end

    if job.remaining <= 0 then
        self:Finish()
        return
    end

    if self.fire_cd > 0 then
        return
    end

    -- 找第一个材料齐备的步骤开炮(不按蓝图顺序)
    local missing_any = false
    for i, s in ipairs(job.steps) do
        if job.pending[i] then
            if self:HasMaterials(s) and self:TakeMaterials(s) then
                self:SetState("BUILDING")
                self.fire_cd = CCBP.BUILD_INTERVAL
                self:Fire(s)
                job.pending[i] = nil
                job.remaining = job.remaining - 1
                self:UpdateMatsText()
                return
            else
                missing_any = true
            end
        end
    end

    if missing_any and not waiting then
        self:SetState("WAITING_MATERIAL")
        local parts = AggregateMissing(self)
        local mt = table.concat(parts, ", ")
        self:Say(mt ~= "" and ("等待材料: " .. mt) or "等待材料… 请把材料放进大炮附近的箱子")
        self:UpdateMatsText()
    end
end

function ConstructionCannon:Finish()
    local job = self.job
    self.job = nil
    self:SetState("COMPLETED")
    self:RefreshBlueprintSlot()
    -- 完成报告延迟到最后一发炮弹落地之后(报告里才能含最后一栋)
    self.inst:DoTaskInTime(CCBP.FLIGHT_TIME + 0.3, function()
        self:Say(string.format("施工完成: 成功%d个, 跳过%d个", job.built or 0, job.skipped or 0))
    end)
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
    print("[CCBP] 施工队列: " .. tostring(bpname or "蓝图") .. " 共" .. #steps .. "步")
    self.job = {
        steps = steps,
        pending = {},
        remaining = #steps,
        built = 0,
        skipped = 0,
        cost_acc = {},
        mats_lines = {},
    }
    for i = 1, #steps do
        self.job.pending[i] = true
    end

    -- 汇总整单材料需求(展示用, 按 *_item 配方产出数量分摊)
    local totals = {}
    for _, s in ipairs(steps) do
        local recipe, per = ResolveRecipe(s.prefab)
        if recipe ~= nil then
            for _, ing in ipairs(recipe.ingredients) do
                if ing ~= nil and ing.type ~= nil and (ing.amount or 0) > 0 then
                    totals[ing.type] = (totals[ing.type] or 0) + ing.amount / per
                end
            end
        end
    end
    for t, amt in pairs(totals) do
        local label = STRINGS.NAMES[string.upper(t)] or t
        self.job.mats_lines[#self.job.mats_lines + 1] = label .. " x" .. tostring(math.ceil(amt - 0.000001))
    end
    table.sort(self.job.mats_lines)
    -- 行数上限(net_string 容量保护)
    while #self.job.mats_lines > 14 do
        table.remove(self.job.mats_lines)
    end

    self.fire_cd = 0
    self:SetState("CHECKING")
    self:UpdateMatsText()
    self:Say("开始施工: " .. tostring(bpname or "蓝图") .. " (" .. #steps .. "个结构)")
    self:StartTicker()
    return true
end

function ConstructionCannon:Cancel()
    if self.job ~= nil then
        self.job.cancelled = true -- 中止还在飞行中的炮弹
        self.job = nil
        self:SetState("IDLE")
        self:UpdateMatsText()
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
