-- 蓝图校验: 把 Base Projection JSON 的解析结果转换成内部蓝图格式
-- 输入 raw: { x, y, z, idx?, name?, data = { {prefab, x, y, z, rotation?, scale?, layer?, build?, bank?, anim?} } }
--   注: Base Projection 的 item.x/z 是绝对世界坐标, 顶层 x/z 是录制原点
-- 输出 bp: { id, name, origin = {x, z}, structures = { {prefab, x, z, rot, scale, layer, build, bank, anim} } }
--   注: 内部格式的 structures.x/z 是相对 origin 的偏移(规格要求的蓝图格式), y 按惯例丢弃
local CCBP = require "ccbp_config"

local Validator = {}

local function finite_num(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 只允许"可施工"的 prefab: 有 placer 配方 / 有 *_item 部署套件 / 墙与栅栏
local function IsBuildablePrefab(p)
    local r = AllRecipes[p]
    if r ~= nil and r.placer ~= nil then
        return true
    end
    if AllRecipes[p .. "_item"] ~= nil then
        return true
    end
    if string.sub(p, 1, 5) == "wall_" or string.sub(p, 1, 6) == "fence_" then
        return true
    end
    return false
end

function Validator.SanitizeName(raw, fallback)
    if type(raw) == "string" and #raw > 0 then
        return raw
    end
    return fallback or "未命名蓝图"
end

function Validator.SanitizeId(stem)
    local id = string.gsub(tostring(stem), "[^%w%-%._]", "_")
    if id == nil or #id == 0 then
        id = "blueprint"
    end
    return id
end

-- 返回 bp 或 nil, err
function Validator.Validate(raw, stem)
    if type(raw) ~= "table" then
        return nil, "根节点不是对象"
    end
    if type(raw.data) ~= "table" or #raw.data <= 0 then
        return nil, "缺少 data 结构数组"
    end
    if not finite_num(raw.x) or not finite_num(raw.z) then
        return nil, "缺少顶层原点坐标 x/z"
    end
    if #raw.data > CCBP.MAX_STRUCTS then
        return nil, "结构数超过上限 " .. CCBP.MAX_STRUCTS
    end

    local id = Validator.SanitizeId(stem)
    local bp = {
        id = id,
        name = Validator.SanitizeName(raw.name, id),
        origin = { x = raw.x, z = raw.z },
        structures = {},
    }

    local seen = {}
    local rejected = 0
    for _, item in ipairs(raw.data) do
        if type(item) ~= "table"
            or type(item.prefab) ~= "string" or #item.prefab == 0
            or not finite_num(item.x) or not finite_num(item.z)
            or (item.rotation ~= nil and not finite_num(item.rotation))
            or (item.layer ~= nil and not finite_num(item.layer)) then
            rejected = rejected + 1
        elseif Prefabs[item.prefab] == nil or not IsBuildablePrefab(item.prefab) then
            -- 未知或不支持施工的 prefab(生物/物品等), 跳过
            rejected = rejected + 1
        else
            local scale = nil
            if type(item.scale) == "table"
                and finite_num(item.scale[1]) and finite_num(item.scale[2]) and finite_num(item.scale[3])
                and (item.scale[1] ~= 1 or item.scale[2] ~= 1 or item.scale[3] ~= 1) then
                scale = { item.scale[1], item.scale[2], item.scale[3] }
            end

            local st = {
                prefab = item.prefab,
                -- 转为相对 origin 的偏移, 保留2位小数
                x = math.floor((item.x - raw.x) * 100 + 0.5) / 100,
                z = math.floor((item.z - raw.z) * 100 + 0.5) / 100,
                rot = math.floor((item.rotation or 0) * 10 + 0.5) / 10,
                scale = scale,
                layer = (item.layer ~= nil and item.layer ~= 6) and item.layer or nil,
                build = (type(item.build) == "string" and item.build ~= "") and item.build or nil,
                bank = (type(item.bank) == "string" and item.bank ~= "") and item.bank or nil,
                anim = (type(item.anim) == "string" and item.anim ~= "") and item.anim or nil,
            }

            local key = st.prefab .. ":" .. st.x .. ":" .. st.z .. ":" .. st.rot
            if seen[key] == nil then
                seen[key] = true
                bp.structures[#bp.structures + 1] = st
            end
        end
    end

    if #bp.structures <= 0 then
        return nil, "没有可施工的结构(全部被过滤或为空)"
    end
    bp.rejected = rejected
    return bp
end

return Validator
