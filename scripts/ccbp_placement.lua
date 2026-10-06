-- 客户端放置系统(固定标记式):
--   拿起蓝图 → 投影出现在"上一次确认的位置"(固定不动, 不跟随鼠标)
--   右键 = 把投影移动到当前鼠标位置并确认(在此之前投影绝不移动)
--   Q/E = 原地旋转(即时同步服务器), ESC = 收起投影
--   蓝图放回背包 → 投影保持固定; 放入大炮蓝图槽 → [开始施工]
local CCBP = require "ccbp_config"
local TransformCC = require "ccbp_transform"
local Ghosts = require "ccbp_ghosts"
local UI = require "ccbp_uiscreens"

local Placement = {
    mode = CCBP.MODE.INACTIVE, -- INACTIVE / LOADING / HOLDING / PLACED
    id = nil,
    bp = nil,                   -- 蓝图数据缓存(避免重复拉取)
    active_item = nil,          -- 手上的蓝图物品(客户端replica)
    ox = 0,
    oz = 0,
    q = 0,
    prev_secondary = false,
    prev_escape = false,
    prev_q = false,
    prev_e = false,
    load_tried = 0,
    deadline = 0,
    cool_until = 0,
    task = nil,
}

-- 手持蓝图期间拦截右键(右键由本模块处理为"移动投影到鼠标位置并确认")
local BlockedSecondary = { [CONTROL_SECONDARY] = true }

function Placement.IsActive()
    return Placement.mode ~= CCBP.MODE.INACTIVE
end

-- 由 modmain 的 AddComponentPostInit("playercontroller") 调用
function Placement.IsControlBlocked(control)
    if Placement.mode == CCBP.MODE.HOLDING or Placement.mode == CCBP.MODE.LOADING then
        return BlockedSecondary[control] == true
    end
    return false
end

-- 拿起蓝图: 优先用缓存数据, 否则向服务器拉取
function Placement.Start(id, active_item)
    if Placement.IsActive() then
        Placement.Exit()
    end
    Placement.id = id
    Placement.active_item = active_item
    if Placement.bp ~= nil and Placement.bp.id == id then
        Placement.EnterHold()
        return
    end
    Placement.mode = CCBP.MODE.LOADING
    Placement.load_tried = 0
    Placement.deadline = GetTime() + CCBP.LOAD_TIMEOUT
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "RequestBlueprintData"), id)
    UI.Toast("手持蓝图: 右键把投影固定到鼠标位置")
    if Placement.task == nil and ThePlayer ~= nil then
        Placement.task = ThePlayer:DoPeriodicTask(FRAMES, Placement.Update)
    end
end

-- 投影出现: 固定在"上一次确认的位置"(netvar 同步), 没有则当前鼠标位置
function Placement.EnterHold()
    Placement.mode = CCBP.MODE.HOLDING
    local pos = TheInput:GetWorldPosition()
    Placement.ox = TransformCC.Snap(pos ~= nil and pos.x or 0, CCBP.SNAP)
    Placement.oz = TransformCC.Snap(pos ~= nil and pos.z or 0, CCBP.SNAP)
    Placement.q = 0
    local item = Placement.active_item
    if item ~= nil and item.net_plc ~= nil and item.net_plc:value() then
        Placement.ox = item.net_plcx:value()
        Placement.oz = item.net_plcz:value()
        Placement.q = item.net_plcq:value() % 4
    end
    local ok_n, failed = Ghosts.SpawnFor(Placement.bp)
    Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, true)
    Placement.prev_secondary = TheInput:IsControlPressed(CONTROL_SECONDARY)
    Placement.prev_escape = TheInput:IsKeyDown(KEY_ESCAPE)
    Placement.prev_q = false
    Placement.prev_e = false
    if failed ~= nil and failed > 0 then
        UI.Toast(string.format("蓝图就绪: %d个结构, %d个无法预览", ok_n, failed))
    end
end

-- 服务器蓝图数据下发完成(由 ccbp_netdata 回调)
function Placement.OnBlueprintData(bp)
    if Placement.mode ~= CCBP.MODE.LOADING or bp == nil then
        return
    end
    Placement.bp = bp
    Placement.EnterHold()
end

function Placement.SetRotation(q)
    q = (math.floor(q) % 4 + 4) % 4
    if q ~= Placement.q then
        Placement.q = q
        Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, true)
        -- 原地旋转即时同步服务器, 保证投影显示与服务器记录一致
        SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "PlaceBlueprint"),
            Placement.id, Placement.ox, Placement.oz, Placement.q)
        UI.Toast("朝向 " .. (Placement.q % 4) * 90 .. "°")
    end
end

-- 右键: 投影移动到当前鼠标位置并确认(固定)
function Placement.MoveAndConfirm()
    local pos = TheInput:GetWorldPosition()
    if pos ~= nil then
        Placement.ox = TransformCC.Snap(pos.x, CCBP.SNAP)
        Placement.oz = TransformCC.Snap(pos.z, CCBP.SNAP)
    end
    Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, false)
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "PlaceBlueprint"),
        Placement.id, Placement.ox, Placement.oz, Placement.q)
    UI.Toast("投影已固定在此位置")
end

function Placement.Exit()
    Placement.mode = CCBP.MODE.INACTIVE
    Placement.bp = nil
    Placement.id = nil
    Placement.active_item = nil
    if Placement.task ~= nil then
        Placement.task:Cancel()
        Placement.task = nil
    end
    Ghosts.Clear()
end

function Placement.Update()
    local player = ThePlayer
    if player == nil or not player:IsValid() then
        Placement.Exit()
        return
    end

    if Placement.mode == CCBP.MODE.LOADING then
        local esc = TheInput:IsKeyDown(KEY_ESCAPE)
        if esc and not Placement.prev_escape then
            Placement.Exit()
            return
        end
        Placement.prev_escape = esc

        if GetTime() > Placement.deadline then
            Placement.load_tried = Placement.load_tried + 1
            if Placement.load_tried > 1 then
                UI.Toast("读取蓝图数据失败, 请重新拿起蓝图")
                Placement.cool_until = GetTime() + 5
                Placement.Exit()
            else
                Placement.deadline = GetTime() + CCBP.LOAD_TIMEOUT
                SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "RequestBlueprintData"), Placement.id)
            end
        end

    elseif Placement.mode == CCBP.MODE.HOLDING then
        -- ESC 收起投影
        local esc = TheInput:IsKeyDown(KEY_ESCAPE)
        if esc and not Placement.prev_escape then
            Placement.Exit()
            return
        end
        Placement.prev_escape = esc

        -- Q/E 原地旋转(即时同步)
        local qk = TheInput:IsKeyDown(KEY_Q)
        if qk and not Placement.prev_q then
            Placement.SetRotation(Placement.q - 1)
        end
        Placement.prev_q = qk
        local ek = TheInput:IsKeyDown(KEY_E)
        if ek and not Placement.prev_e then
            Placement.SetRotation(Placement.q + 1)
        end
        Placement.prev_e = ek

        -- 右键 = 投影移动到鼠标位置并固定
        local sec = TheInput:IsControlPressed(CONTROL_SECONDARY)
        if sec and not Placement.prev_secondary then
            Placement.MoveAndConfirm()
        end
        Placement.prev_secondary = sec

    elseif Placement.mode == CCBP.MODE.PLACED then
        -- 投影固定保留(蓝图在背包/大炮里): ESC 收起
        local esc = TheInput:IsKeyDown(KEY_ESCAPE)
        if esc and not Placement.prev_escape then
            Placement.Exit()
            return
        end
        Placement.prev_escape = esc
    end
end

-- 手持蓝图监视(由 modmain 的 AddPlayerPostInit 每帧调用, 只对本地玩家生效):
--   拿起蓝图 → 显示投影(HOLDING); 放回背包 → 投影保持固定(PLACED)
function Placement.WatchActiveItem(inst)
    if inst ~= ThePlayer then
        return
    end
    local inv = inst.replica ~= nil and inst.replica.inventory or nil
    local active = (inv ~= nil and inv.GetActiveItem ~= nil) and inv:GetActiveItem() or nil
    local isbp = active ~= nil and active:HasTag("ccbp_blueprint")
        and active.net_bpid ~= nil and active.net_bpid:value() ~= ""

    if isbp then
        local id = active.net_bpid:value()
        if Placement.mode == CCBP.MODE.INACTIVE then
            if GetTime() >= Placement.cool_until then
                Placement.Start(id, active)
            end
        elseif Placement.mode == CCBP.MODE.PLACED and Placement.active_item ~= active then
            -- 重新拿起(上次是放回背包): 投影回到手上(仍然固定)
            Placement.active_item = active
            Placement.mode = CCBP.MODE.HOLDING
            Placement.prev_secondary = TheInput:IsControlPressed(CONTROL_SECONDARY)
            Placement.prev_escape = TheInput:IsKeyDown(KEY_ESCAPE)
        end
    else
        if Placement.mode == CCBP.MODE.HOLDING then
            -- 放回背包/放下: 投影保持固定
            Placement.mode = CCBP.MODE.PLACED
            Placement.active_item = nil
        elseif Placement.mode == CCBP.MODE.LOADING then
            Placement.Exit()
        end
    end
end

-- ==================== B键快捷键: 直接打开蓝图库 ====================
local KEY_B_SAFE = KEY_B or 98

local function OnBrowseKey()
    if Placement.IsActive() then
        return
    end
    local screen = TheFrontEnd ~= nil and TheFrontEnd:GetActiveScreen() or nil
    if screen ~= nil and screen.name ~= nil and screen.name ~= "HUD" then
        return -- 有界面打开时忽略(避免打断文本输入)
    end
    UI.OnOpenBrowser("", STRINGS.NAMES.CONSTRUCTION_CANNON or "建筑大炮")
end

if not TheNet:IsDedicated() then
    TheInput:AddKeyUpHandler(KEY_B_SAFE, OnBrowseKey)
end

return Placement
