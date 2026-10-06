-- 蓝图库(世界组件, 仅服务器)
-- 保存 id -> 完整蓝图数据; 蓝图物品只存 id
-- 数据来源: 世界加载时从 unsafedata/ 读取 + 世界存档持久化(删了JSON也不会丢已加载的蓝图)
local CCBP = require "ccbp_config"
local Loader = require "ccbp_jsonloader"

local CCBPStore = Class(function(self, inst)
    self.inst = inst
    self.blueprints = {}
    self.errors = {}
    self.inst:DoTaskInTime(0, function()
        self:LoadFromDisk()
    end)
end)

function CCBPStore:LoadFromDisk()
    local bps, errors = Loader.LoadAll()
    for _, bp in ipairs(bps) do
        self.blueprints[bp.id] = bp
    end
    self.errors = errors or {}
    print(string.format("[CCBP] 蓝图库加载完成: %d 张可用, %d 个文件出错", #bps, #self.errors))
    for _, e in ipairs(self.errors) do
        print("[CCBP]   错误:", e.name, "-", e.err)
    end
    self.inst:PushEvent("ccbp_store_loaded")
end

function CCBPStore:Upsert(bp)
    if bp ~= nil and bp.id ~= nil then
        self.blueprints[bp.id] = bp
    end
end

function CCBPStore:Get(id)
    if id == nil then
        return nil
    end
    return self.blueprints[id]
end

function CCBPStore:Count()
    local n = 0
    for _ in pairs(self.blueprints) do
        n = n + 1
    end
    return n
end

function CCBPStore:List()
    local list = {}
    for id, bp in pairs(self.blueprints) do
        list[#list + 1] = {
            id = id,
            name = bp.name or id,
            count = bp.structures ~= nil and #bp.structures or 0,
        }
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

function CCBPStore:OnSave()
    return { data = json.encode(self.blueprints) }
end

function CCBPStore:OnLoad(data)
    if data == nil or type(data.data) ~= "string" then
        return
    end
    local ok, decoded = pcall(json.decode, data.data)
    if ok and type(decoded) == "table" then
        -- 磁盘文件(稍后异步同步读取)会覆盖同名id, 这里只补齐磁盘上已删除的
        for id, bp in pairs(decoded) do
            if self.blueprints[id] == nil and type(bp) == "table" and type(bp.structures) == "table" then
                self.blueprints[id] = bp
            end
        end
    end
end

return CCBPStore
