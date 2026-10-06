-- 建筑蓝图物品组件(服务器): 只保存 blueprint_id, 完整数据在 ccbp_store
local ConstructionBlueprint = Class(function(self, inst)
    self.inst = inst
    self.id = nil
    self.bpname = nil
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

function ConstructionBlueprint:OnSave(data)
    data.id = self.id
    data.bpname = self.bpname
end

function ConstructionBlueprint:OnLoad(data)
    if data ~= nil and data.id ~= nil then
        self:SetID(data.id, data.bpname)
    end
end

return ConstructionBlueprint
