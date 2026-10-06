-- 建筑蓝图物品组件(服务器): 只保存 blueprint_id 与"已确认的投影位置", 完整数据在 ccbp_store
local ConstructionBlueprint = Class(function(self, inst)
    self.inst = inst
    self.id = nil
    self.bpname = nil
    self.placement = nil -- {x=, z=, q=} 已确认的投影位置(手持蓝图右键确认)
end)

function ConstructionBlueprint:GetID()
    return self.id
end

function ConstructionBlueprint:SetID(id, bpname)
    self.id = id
    self.bpname = bpname
    if self.inst.net_bpid ~= nil then
        self.inst.net_bpid:set(id or "")
    end
    if self.inst.components.named ~= nil then
        self.inst.components.named:SetName("蓝图·" .. tostring(bpname or id or "未知"))
    end
end

-- 投影位置(手持蓝图右键确认后由服务器写入, 同时同步 netvar 供客户端还原投影)
function ConstructionBlueprint:SetPlacement(ox, oz, q)
    self.placement = { x = ox, z = oz, q = q }
    if self.inst.net_plc ~= nil then
        self.inst.net_plc:set(true)
        self.inst.net_plcx:set(ox)
        self.inst.net_plcz:set(oz)
        self.inst.net_plcq:set(math.floor(q) % 4)
    end
end

function ConstructionBlueprint:GetPlacement()
    return self.placement
end

-- 注意: DST 组件的 OnSave 约定是"返回数据表"(不是接收 data 参数)
function ConstructionBlueprint:OnSave()
    local data = {
        id = self.id,
        bpname = self.bpname,
    }
    if self.placement ~= nil then
        data.placement = self.placement
    end
    return data
end

function ConstructionBlueprint:OnLoad(data)
    if data ~= nil and data.id ~= nil then
        self:SetID(data.id, data.bpname)
    end
    if data ~= nil and data.placement ~= nil and data.placement.x ~= nil then
        self.placement = data.placement
    end
end

return ConstructionBlueprint
