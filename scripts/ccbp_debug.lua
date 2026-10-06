-- 调试命令(仅当 mod 选项 ccbp_debug 开启时由 modmain 加载)
-- c_ccbp_reload()          重读 unsafedata/
-- c_ccbp_list()            列出蓝图库
-- c_ccbp_load("文件名")    手动读取一个 JSON
-- c_ccbp_give(["id"])      给所有在线玩家发蓝图(默认第一张)
local CCBP = require "ccbp_config"

local function GetStore()
    if TheWorld == nil then
        return nil
    end
    return TheWorld.components.ccbp_store
end

function c_ccbp_reload()
    local store = GetStore()
    if store == nil then
        print("[CCBP] 世界尚未加载")
        return
    end
    store:LoadFromDisk()
    print("[CCBP] 已重载, 共 " .. store:Count() .. " 张蓝图")
end

function c_ccbp_list()
    local store = GetStore()
    if store == nil then
        print("[CCBP] 世界尚未加载")
        return
    end
    for _, e in ipairs(store:List()) do
        print(string.format("[CCBP] %s | %s | %d个结构", e.id, e.name, e.count))
    end
    print("[CCBP] 共 " .. store:Count() .. " 张")
end

function c_ccbp_load(name)
    local Loader = require "ccbp_jsonloader"
    local bp, err = Loader.ReadBlueprintFile(name)
    if bp == nil then
        print("[CCBP] 读取失败: " .. tostring(err))
        return
    end
    local store = GetStore()
    if store ~= nil then
        store:Upsert(bp)
    end
    print(string.format("[CCBP] 已读取: %s (%s) %d个结构, 过滤%d个", bp.id, bp.name, #bp.structures, bp.rejected or 0))
end

function c_ccbp_give(id)
    local store = GetStore()
    if store == nil then
        print("[CCBP] 世界尚未加载")
        return
    end
    local bp = store:Get(id)
    if bp == nil then
        local list = store:List()
        bp = list[1] ~= nil and store:Get(list[1].id) or nil
    end
    if bp == nil then
        print("[CCBP] 没有可用蓝图")
        return
    end
    for _, p in ipairs(AllPlayers) do
        if p.components ~= nil and p.components.inventory ~= nil then
            local item = SpawnPrefab("projection_blueprint")
            if item ~= nil then
                item.components.construction_blueprint:SetID(bp.id, bp.name)
                p.components.inventory:GiveItem(item)
            end
        end
    end
    print("[CCBP] 已发放蓝图: " .. bp.name)
end

print("[CCBP] 调试命令已启用: c_ccbp_reload / c_ccbp_list / c_ccbp_load / c_ccbp_give")
