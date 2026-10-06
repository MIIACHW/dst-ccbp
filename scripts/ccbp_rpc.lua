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

-- 手持蓝图右键: 确认投影位置(记录到蓝图物品上, 并把蓝图放回背包)
function RPC.PlaceBlueprint(player, id, ox, oz, q)
    if not (isstr(id) and isnum(ox) and isnum(oz) and isnum(q)) then
        return
    end
    q = math.floor(q) % 4
    if math.abs(ox) > 10000 or math.abs(oz) > 10000 then
        return
    end
    local store = GetStore()
    local bp = store ~= nil and store:Get(id) or nil
    if bp == nil then
        SayTo(player, "蓝图数据不存在")
        return
    end

    -- 在玩家物品中找到这张蓝图(手持或背包)
    local inv = player.components.inventory
    local target = nil
    if inv ~= nil then
        if inv.activeitem ~= nil and inv.activeitem.components.construction_blueprint ~= nil
            and inv.activeitem.components.construction_blueprint:GetID() == id then
            target = inv.activeitem
        end
        if target == nil and inv.itemslots ~= nil then
            for _, it in pairs(inv.itemslots) do
                if it ~= nil and it.components ~= nil and it.components.construction_blueprint ~= nil
                    and it.components.construction_blueprint:GetID() == id then
                    target = it
                    break
                end
            end
        end
    end
    if target == nil or target.components.construction_blueprint == nil then
        SayTo(player, "找不到蓝图物品")
        return
    end

    target.components.construction_blueprint:SetPlacement(ox, oz, q)
    if inv ~= nil and inv.ReturnActiveItem ~= nil then
        inv:ReturnActiveItem()
    end
    NetData.SendToast(player, "投影位置已确认, 蓝图已放回背包\n放入大炮蓝图槽后点[开始施工]")
end

-- 大炮[开始施工]: 读取蓝图槽中已确认投影的蓝图并开始施工
function RPC.StartConstruction(player, uid)
    if not isstr(uid) then
        return
    end
    local cc = GetCannonByUID(uid)
    if cc == nil or cc.inst == nil or not cc.inst:IsValid() then
        SayTo(player, "找不到目标建筑大炮")
        return
    end
    local ok, msg = cc:TryStartFromBlueprint()
    SayTo(player, msg)
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
