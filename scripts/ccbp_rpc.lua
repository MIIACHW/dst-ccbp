-- Mod RPC 处理函数(逻辑在这里, 由 modmain 用 AddModRPCHandler 注册)
-- 全部在服务器执行; 客户端发来的所有数据都视为不可信, 逐一校验
local CCBP = require "ccbp_config"
local TransformCC = require "ccbp_transform"
local NetData = require "ccbp_netdata"
local Loader = require "ccbp_jsonloader"

local RPC = {}

local function isstr(v)
    return type(v) == "string"
end

local function isnum(v)
    return type(v) == "number" and v == v
end

local function GetStore()
    if TheWorld == nil then
        return nil
    end
    return TheWorld.components.ccbp_store
end

local function SayTo(player, msg)
    if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
        player.components.talker:Say(msg)
    end
end

local function GetCannonByUID(uid)
    local ok, class = pcall(require, "components/constructioncannon")
    if not ok or class == nil or class.GetByUID == nil then
        return nil
    end
    return class.GetByUID(uid)
end

-- 客户端请求蓝图列表
function RPC.RequestList(player)
    print("[CCBP] 服务器收到列表请求")
    local store = GetStore()
    local list = store ~= nil and store:List() or {}
    NetData.SendList(player, list)
end

-- 客户端请求蓝图完整数据(用于投影渲染)
function RPC.RequestBlueprintData(player, id)
    if not isstr(id) then
        return
    end
    local store = GetStore()
    local bp = store ~= nil and store:Get(id) or nil
    if bp == nil then
        NetData.SendToast(player, "蓝图不存在: " .. id)
        return
    end
    NetData.SendBlueprint(player, bp)
end

-- 莎草纸刻录蓝图
function RPC.BurnBlueprint(player, id)
    print("[CCBP] 服务器收到刻录请求: " .. tostring(id))
    if not isstr(id) or player == nil or player.components == nil then
        return
    end
    local store = GetStore()
    local bp = store ~= nil and store:Get(id) or nil
    if bp == nil then
        NetData.SendToast(player, "刻录失败: 蓝图不存在(" .. id .. ")")
        return
    end
    local inv = player.components.inventory
    if inv == nil then
        return
    end
    local has = inv:Has("papyrus", 1)
    if not has then
        NetData.SendToast(player, "刻录失败: 需要 莎草纸×1")
        return
    end
    inv:ConsumeByName("papyrus", 1)
    local item = SpawnPrefab("projection_blueprint")
    if item == nil or item.components.construction_blueprint == nil then
        return
    end
    item.components.construction_blueprint:SetID(bp.id, bp.name)
    inv:GiveItem(item)
    NetData.SendToast(player, "刻录成功: " .. bp.name)
end

-- 最终确认施工: blueprint_id + origin + rotation + target cannon
function RPC.ConfirmConstruction(player, id, ox, oz, q, uid)
    print("[CCBP] 服务器收到施工确认: id=" .. tostring(id) .. " q=" .. tostring(q) .. " uid=" .. tostring(uid))
    if not (isstr(id) and isnum(ox) and isnum(oz) and isnum(q) and isstr(uid)) then
        print("[CCBP] 施工确认被拒: 参数类型非法")
        return
    end
    q = math.floor(q) % 4
    if math.abs(ox) > 10000 or math.abs(oz) > 10000 then
        return
    end

    local store = GetStore()
    local bp = store ~= nil and store:Get(id) or nil
    if bp == nil then
        SayTo(player, "蓝图数据不存在或未加载")
        return
    end

    local cc = GetCannonByUID(uid)
    if cc == nil or cc.inst == nil or not cc.inst:IsValid() then
        SayTo(player, "找不到目标建筑大炮")
        return
    end

    -- 重新验证: 投影中心必须在大炮施工范围内
    local cx, cy, cz = cc.inst.Transform:GetWorldPosition()
    local dx, dz = ox - cx, oz - cz
    local maxr = CCBP.CANNON_RANGE + 5
    if dx * dx + dz * dz > maxr * maxr then
        SayTo(player, "投影位置离大炮太远")
        return
    end

    local steps = TransformCC.ComputeSteps(bp, ox, oz, q)
    local ok, msg = cc:Enqueue(steps, bp.name)
    if ok then
        SayTo(player, "已加入施工队列: " .. bp.name .. " (" .. #steps .. "个结构)")
    else
        SayTo(player, msg)
    end
end

function RPC.CancelConstruction(player, uid)
    print("[CCBP] 服务器收到取消施工请求")
    if not isstr(uid) then
        return
    end
    local cc = GetCannonByUID(uid)
    if cc ~= nil then
        cc:Cancel()
    end
end

-- 手动按文件名读取蓝图(unsafedata/ 或 MOD blueprints/ 目录)
function RPC.LoadBlueprintFile(player, name)
    if not isstr(name) or player == nil then
        return
    end
    local bp, err = Loader.ReadBlueprintFile(name)
    if bp == nil then
        NetData.SendToast(player, "读取失败: " .. tostring(err))
        return
    end
    local store = GetStore()
    if store ~= nil then
        store:Upsert(bp)
    end
    NetData.SendToast(player, "已读取蓝图: " .. bp.name .. " (" .. #bp.structures .. "个结构)")
    RPC.RequestList(player)
end

-- 重新从磁盘加载全部蓝图
function RPC.ReloadStore(player)
    local store = GetStore()
    if store == nil then
        return
    end
    store:LoadFromDisk()
    NetData.SendToast(player, "蓝图库已重载: 共 " .. store:Count() .. " 张")
    RPC.RequestList(player)
end

return RPC
