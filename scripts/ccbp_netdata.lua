-- 服务器 → 客户端 数据传输
-- 基于 Klei 官方 CLIENT_MOD_RPC (AddClientModRPCHandler / SendModRPCToClient)
-- payload 按结构逐条分块(每块一个短 JSON 字符串, 远小于 RPC 字符串限制),
-- 多块按每 tick DATA_CHUNKS_PER_TICK 分批发送, 避免触发限流
-- 客户端接收后按 seq 重组成完整蓝图/列表
local CCBP = require "ccbp_config"

local NetData = {
    pending_bp = {},   -- id -> {total, parts, got}
    pending_list = nil,
    on_blueprint = nil, -- 客户端: 蓝图数据组装完成回调(bp)
    on_list = nil,      -- 客户端: 列表组装完成回调(list)
}

-- ==================== 服务器端发送 ====================

local function GetClientRPC(name)
    local ok, rpc = pcall(GetClientModRPC, CCBP.MOD_NS, name)
    if ok and rpc ~= nil then
        return rpc
    end
    return nil
end

local function SendChunks(player, rpc_name, chunks, id)
    local rpc = GetClientRPC(rpc_name)
    print("[CCBP] SendChunks(" .. rpc_name .. "): rpc=" .. tostring(rpc ~= nil) .. " 共" .. #chunks .. "块")
    if rpc == nil or player == nil or player.userid == nil then
        return
    end
    local total = #chunks
    for i, payload in ipairs(chunks) do
        local batch = math.floor((i - 1) / CCBP.DATA_CHUNKS_PER_TICK)
        if batch <= 0 then
            SendModRPCToClient(rpc, player.userid, id, i, total, payload)
        else
            player:DoTaskInTime(batch * FRAMES, function()
                if player:IsValid() then
                    SendModRPCToClient(rpc, player.userid, id, i, total, payload)
                end
            end)
        end
    end
end

-- 发送完整蓝图数据(结构逐条分块)
function NetData.SendBlueprint(player, bp)
    if bp == nil or bp.structures == nil then
        return
    end
    local id = tostring(bp.id)
    local chunks = { json.encode({ m = { n = bp.name or id } }) }
    for _, st in ipairs(bp.structures) do
        chunks[#chunks + 1] = json.encode({
            s = {
                {
                    p = st.prefab,
                    x = st.x,
                    z = st.z,
                    r = st.rot,
                    sc = st.scale,
                    l = st.layer,
                    b = st.build,
                    k = st.bank,
                    a = st.anim,
                },
            },
        })
    end
    SendChunks(player, "BPData", chunks, id)
end

-- 发送蓝图列表 [{id, name, count}]
function NetData.SendList(player, list)
    list = list or {}
    local chunks = {}
    for _, e in ipairs(list) do
        chunks[#chunks + 1] = json.encode({ l = { { i = e.id, n = e.name, c = e.count } } })
    end
    if #chunks == 0 then
        -- 空列表也要发一块, 客户端才能结束"加载中"状态
        chunks[1] = json.encode({ l = {} })
    end
    SendChunks(player, "ListData", chunks, "list")
end

function NetData.SendToast(player, msg)
    local rpc = GetClientRPC("Toast")
    if rpc ~= nil and player ~= nil and player.userid ~= nil then
        SendModRPCToClient(rpc, player.userid, tostring(msg))
    end
end

function NetData.SendOpenBrowser(player, cannon_uid, cannon_name)
    local rpc = GetClientRPC("OpenBrowser")
    print("[CCBP] SendOpenBrowser: rpc=" .. tostring(rpc ~= nil) .. " userid=" .. tostring(player ~= nil and player.userid or "nil"))
    if rpc ~= nil and player ~= nil and player.userid ~= nil then
        SendModRPCToClient(rpc, player.userid, tostring(cannon_uid), tostring(cannon_name))
    end
end

-- ==================== 客户端接收处理 ====================
-- (由 modmain 用 AddClientModRPCHandler 注册, 参数为 RPC 变参)

function NetData.OnBlueprintChunk(id, seq, total, payload)
    if type(id) ~= "string" or type(seq) ~= "number" or type(total) ~= "number" or type(payload) ~= "string" then
        return
    end
    local p = NetData.pending_bp[id]
    if p == nil or p.total ~= total then
        p = { total = total, parts = {}, got = 0 }
        NetData.pending_bp[id] = p
    end
    local key = tostring(math.floor(seq))
    if p.parts[key] == nil then
        p.got = p.got + 1
    end
    p.parts[key] = payload

    if p.got >= p.total then
        NetData.pending_bp[id] = nil
        local bp = { id = id, name = id, origin = { x = 0, z = 0 }, structures = {} }
        for i = 1, p.total do
            local ok, decoded = pcall(json.decode, p.parts[tostring(i)] or "")
            if ok and type(decoded) == "table" then
                if decoded.m ~= nil and type(decoded.m.n) == "string" then
                    bp.name = decoded.m.n
                end
                if decoded.s ~= nil and type(decoded.s) == "table" then
                    for _, it in ipairs(decoded.s) do
                        bp.structures[#bp.structures + 1] = {
                            prefab = it.p,
                            x = it.x,
                            z = it.z,
                            rot = it.r or 0,
                            scale = it.sc,
                            layer = it.l,
                            build = it.b,
                            bank = it.k,
                            anim = it.a,
                        }
                    end
                end
            end
        end
        if #bp.structures > 0 and NetData.on_blueprint ~= nil then
            NetData.on_blueprint(bp)
        end
    end
end

function NetData.OnListChunk(id, seq, total, payload)
    if type(seq) ~= "number" or type(total) ~= "number" or type(payload) ~= "string" then
        return
    end
    local p = NetData.pending_list
    if p == nil or p.total ~= total then
        p = { total = total, parts = {}, got = 0 }
        NetData.pending_list = p
    end
    local key = tostring(math.floor(seq))
    if p.parts[key] == nil then
        p.got = p.got + 1
    end
    p.parts[key] = payload

    if p.got >= p.total then
        NetData.pending_list = nil
        local list = {}
        for i = 1, p.total do
            local ok, decoded = pcall(json.decode, p.parts[tostring(i)] or "")
            if ok and type(decoded) == "table" and decoded.l ~= nil then
                for _, it in ipairs(decoded.l) do
                    list[#list + 1] = { id = it.i, name = it.n, count = it.c or 0 }
                end
            end
        end
        if NetData.on_list ~= nil then
            NetData.on_list(list)
        end
    end
end

return NetData
