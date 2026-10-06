-- 客户端放置/确认状态机
-- LOADING: 等服务器下发蓝图数据
-- PLACING: 投影跟随鼠标, 右键确认位置(玩家可正常移动)
-- CONFIRMING: 玩家锁定(拦截输入), WASD 微调 + Q/E 旋转(参考DST摄像机方向), 右键最终确认
local CCBP = require "ccbp_config"
local TransformCC = require "ccbp_transform"
local Ghosts = require "ccbp_ghosts"
local UI = require "ccbp_uiscreens"

local KEY_SHIFT_SAFE = KEY_SHIFT or 304

local Placement = {
    mode = CCBP.MODE.INACTIVE,
    id = nil,
    bp = nil,
    ox = 0,
    oz = 0,
    q = 0,
    prev_secondary = false,
    prev_escape = false,
    prev_q = false,
    prev_e = false,
    load_tried = 0,
    deadline = 0,
    target_uid = nil,
    target_scan = 0,
    task = nil,
}

-- 确认模式下拦截的输入(经 modmain 的 playercontroller.OnControl 包装生效)
local BlockedAll = {
    [CONTROL_PRIMARY] = true,
    [CONTROL_SECONDARY] = true,
    [CONTROL_ATTACK] = true,
    [CONTROL_ACTION] = true,
    [CONTROL_INSPECT] = true,
    [CONTROL_MOVE_UP] = true,
    [CONTROL_MOVE_DOWN] = true,
    [CONTROL_MOVE_LEFT] = true,
    [CONTROL_MOVE_RIGHT] = true,
}
-- 放置模式只拦右键(防止误触发右键动作), 移动不受限制
local BlockedSecondary = { [CONTROL_SECONDARY] = true }

function Placement.IsActive()
    return Placement.mode ~= CCBP.MODE.INACTIVE
end

-- 由 modmain 的 AddComponentPostInit("playercontroller") 调用
function Placement.IsControlBlocked(control)
    if Placement.mode == CCBP.MODE.CONFIRMING then
        return BlockedAll[control] == true
    elseif Placement.mode == CCBP.MODE.PLACING then
        return BlockedSecondary[control] == true
    end
    return false
end

function Placement.OnStartPlacement(id)
    if type(id) == "string" then
        Placement.Start(id)
    end
end

function Placement.Start(id)
    print("[CCBP] 客户端开始放置蓝图: " .. tostring(id))
    if Placement.IsActive() then
        Placement.Exit()
    end
    Placement.mode = CCBP.MODE.LOADING
    Placement.id = id
    Placement.bp = nil
    Placement.load_tried = 0
    Placement.deadline = GetTime() + CCBP.LOAD_TIMEOUT
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "RequestBlueprintData"), id)
    UI.Toast("正在读取蓝图数据…")
    if Placement.task == nil and ThePlayer ~= nil then
        Placement.task = ThePlayer:DoPeriodicTask(FRAMES, Placement.Update)
    end
end

-- 服务器蓝图数据下发完成(由 ccbp_netdata 回调)
function Placement.OnBlueprintData(bp)
    print("[CCBP] 客户端收到蓝图数据: " .. tostring(bp ~= nil and bp.name or "nil"))
    if Placement.mode == CCBP.MODE.INACTIVE or bp == nil then
        return
    end
    Placement.bp = bp
    local pos = TheInput:GetWorldPosition()
    Placement.ox = TransformCC.Snap(pos ~= nil and pos.x or 0, CCBP.SNAP)
    Placement.oz = TransformCC.Snap(pos ~= nil and pos.z or 0, CCBP.SNAP)
    Placement.q = 0
    local ok_n, failed = Ghosts.SpawnFor(bp)
    Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, true)
    Placement.mode = CCBP.MODE.PLACING
    Placement.prev_secondary = TheInput:IsControlPressed(CONTROL_SECONDARY)
    Placement.prev_escape = TheInput:IsKeyDown(KEY_ESCAPE)
    if failed > 0 then
        UI.Toast(string.format("蓝图已就绪: %d个结构, %d个无法预览", ok_n, failed))
    else
        UI.Toast("蓝图已就绪: " .. bp.name .. " · 移动鼠标放置, 右键确认位置")
    end
end

function Placement.SetRotation(q)
    q = (math.floor(q) % 4 + 4) % 4
    if q ~= Placement.q then
        Placement.q = q
        Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, true)
        UI.SetConfirmInfo(Placement:ConfirmInfoText())
    end
end

function Placement:ConfirmInfoText()
    local n = Placement.bp ~= nil and #Placement.bp.structures or 0
    local target = "附近没有建筑大炮!"
    if Placement.target_uid ~= nil then
        target = "目标: 附近建筑大炮"
    end
    return string.format("%s · %d个结构 · 朝向 %d°\n%s",
        Placement.bp.name or "?", n, (Placement.q % 4) * 90, target)
end

function Placement:ScanTarget()
    local ents = TheSim:FindEntities(Placement.ox, 0, Placement.oz, CCBP.CANNON_RANGE, { "construction_cannon" })
    local best, bestd = nil, math.huge
    for _, ent in ipairs(ents) do
        if ent:IsValid() and ent.net_uid ~= nil then
            local x, y, z = ent.Transform:GetWorldPosition()
            local d = (x - Placement.ox) * (x - Placement.ox) + (z - Placement.oz) * (z - Placement.oz)
            if d < bestd then
                best = ent
                bestd = d
            end
        end
    end
    Placement.target_uid = best ~= nil and best.net_uid:value() or nil
end

function Placement.EnterConfirm()
    Placement.mode = CCBP.MODE.CONFIRMING
    Placement.prev_secondary = true -- 刚按下的这次右键不算下一次确认
    Placement.prev_escape = TheInput:IsKeyDown(KEY_ESCAPE)
    Placement.prev_q = false
    Placement.prev_e = false
    Placement.target_scan = 0
    -- 锁定玩家: 输入在 OnControl 拦截层被吞掉, 这里停掉正在进行的移动
    local player = ThePlayer
    if player ~= nil and player.components ~= nil then
        pcall(function()
            if player.components.locomotor ~= nil then
                player.components.locomotor:Stop()
            end
        end)
    end
    Placement:ScanTarget()
    UI.ShowConfirm(Placement.bp, Placement:ConfirmInfoText())
end

function Placement.SendConfirm()
    if Placement.target_uid == nil then
        UI.Toast("附近没有建筑大炮, 无法施工")
        return
    end
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "ConfirmConstruction"),
        Placement.id, Placement.ox, Placement.oz, Placement.q, Placement.target_uid)
    UI.Toast("已提交施工请求")
    Placement.Exit()
end

function Placement.Exit()
    Placement.mode = CCBP.MODE.INACTIVE
    Placement.bp = nil
    Placement.id = nil
    Placement.target_uid = nil
    if Placement.task ~= nil then
        Placement.task:Cancel()
        Placement.task = nil
    end
    Ghosts.Clear()
    UI.HideConfirm()
end

function Placement.Update()    local player = ThePlayer
    if player == nil or not player:IsValid() then
        Placement.Exit()
        return
    end

    if Placement.mode == CCBP.MODE.LOADING then
        if GetTime() > Placement.deadline then
            Placement.load_tried = Placement.load_tried + 1
            if Placement.load_tried > 1 then
                UI.Toast("读取蓝图数据超时")
                Placement.Exit()
            else
                Placement.deadline = GetTime() + CCBP.LOAD_TIMEOUT
                SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "RequestBlueprintData"), Placement.id)
            end
        end

    elseif Placement.mode == CCBP.MODE.PLACING then
        -- ESC 取消
        local esc = TheInput:IsKeyDown(KEY_ESCAPE)
        if esc and not Placement.prev_escape then
            Placement.Exit()
            return
        end
        Placement.prev_escape = esc

        -- 投影跟随鼠标
        local pos = TheInput:GetWorldPosition()
        if pos ~= nil then
            local nx = TransformCC.Snap(pos.x, CCBP.SNAP)
            local nz = TransformCC.Snap(pos.z, CCBP.SNAP)
            if nx ~= Placement.ox or nz ~= Placement.oz then
                Placement.ox, Placement.oz = nx, nz
                Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, false)
            end
        end

        -- 右键确认位置 → 进入微调模式
        local sec = TheInput:IsControlPressed(CONTROL_SECONDARY)
        if sec and not Placement.prev_secondary then
            Placement.EnterConfirm()
            return
        end
        Placement.prev_secondary = sec

    elseif Placement.mode == CCBP.MODE.CONFIRMING then
        -- WASD 微调(摄像机相对方向)
        local dx = (TheInput:IsKeyDown(KEY_D) and 1 or 0) - (TheInput:IsKeyDown(KEY_A) and 1 or 0)
        local dy = (TheInput:IsKeyDown(KEY_W) and 1 or 0) - (TheInput:IsKeyDown(KEY_S) and 1 or 0)
        if dx ~= 0 or dy ~= 0 then
            local rv = TheCamera:GetRightVec()
            local dv = TheCamera:GetDownVec()
            -- 与 playercontroller 相同的换算: dir = 右向量*x - 下向量*y
            local dir = (rv * dx - dv * dy):GetNormalized()
            local spd = TheInput:IsKeyDown(KEY_SHIFT_SAFE) and CCBP.CONFIRM_SPEED_SLOW or CCBP.CONFIRM_SPEED
            Placement.ox = TransformCC.Snap(Placement.ox + dir.x * spd * FRAMES, 0.25)
            Placement.oz = TransformCC.Snap(Placement.oz + dir.z * spd * FRAMES, 0.25)
            Ghosts.Apply(Placement.ox, Placement.oz, Placement.q, false)
        end

        -- Q/E 旋转(绕蓝图原点)
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

        -- 定期重新扫描目标大炮
        Placement.target_scan = Placement.target_scan - FRAMES
        if Placement.target_scan <= 0 then
            Placement.target_scan = 0.5
            Placement:ScanTarget()
            UI.SetConfirmInfo(Placement:ConfirmInfoText())
        end

        -- 右键最终确认 / ESC 取消
        local sec = TheInput:IsControlPressed(CONTROL_SECONDARY)
        if sec and not Placement.prev_secondary then
            Placement.SendConfirm()
            return
        end
        Placement.prev_secondary = sec

        local esc = TheInput:IsKeyDown(KEY_ESCAPE)
        if esc and not Placement.prev_escape then
            Placement.Exit()
            return
        end
        Placement.prev_escape = esc
    end
end

-- ==================== B键快捷键: 直接打开蓝图库 ====================
-- 客户端本地直开, 绕开右键动作链路; 同时输出大炮的诊断信息

local KEY_B_SAFE = KEY_B or 98

local function FindNearestCannon()
    local player = ThePlayer
    if player == nil then
        return nil
    end
    local x, y, z = player.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, 40, { "construction_cannon" })
    local best, bestd = nil, math.huge
    for _, ent in ipairs(ents) do
        if ent:IsValid() then
            local ex, ey, ez = ent.Transform:GetWorldPosition()
            local d = (ex - x) * (ex - x) + (ez - z) * (ez - z)
            if d < bestd then
                best = ent
                bestd = d
            end
        end
    end
    return best
end

local function OnBrowseKey()
    if Placement.IsActive() then
        return
    end
    local screen = TheFrontEnd ~= nil and TheFrontEnd:GetActiveScreen() or nil
    if screen ~= nil and screen.name ~= nil and screen.name ~= "HUD" then
        return -- 有界面打开时忽略(避免打断文本输入)
    end
    local cannon = FindNearestCannon()
    local uid = ""
    if cannon ~= nil then
        uid = cannon.net_uid ~= nil and cannon.net_uid:value() or ""
        print(string.format(
            "[CCBP][诊断] B键: 找到大炮 uid=%s inherent动作=%s mod动作同步=%s",
            tostring(uid),
            tostring(cannon.inherentscenealtaction ~= nil),
            tostring(cannon.modactioncomponents ~= nil and cannon.modactioncomponents["dps"] ~= nil)))
    else
        print("[CCBP][诊断] B键: 附近40单位内没有大炮, 以无目标模式打开")
    end
    UI.OnOpenBrowser(uid, STRINGS.NAMES.CONSTRUCTION_CANNON or "建筑大炮")
end

if not TheNet:IsDedicated() then
    TheInput:AddKeyUpHandler(KEY_B_SAFE, OnBrowseKey)
end

return Placement
