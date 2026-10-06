-- 客户端 UI: 蓝图库浏览器 + 施工确认面板 + 顶部提示
local CCBP = require "ccbp_config"
local Screen = require "widgets/screen"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local TextEdit = require "widgets/textedit"

local ROWS = 8
local BUTTON = "images/global_redux.xml"
local BTN_NORMAL = "button_carny_long_normal.tex"
local BTN_HOVER = "button_carny_long_hover.tex"
local BTN_DISABLED = "button_carny_long_disabled.tex"
local BTN_DOWN = "button_carny_long_down.tex"

local UI = {
    browser = nil,
    confirm = nil,
}

local PlacementRef -- 循环依赖由 placement 模块注入
function UI.SetPlacementRef(p)
    PlacementRef = p
end

function UI.Toast(msg)
    local player = ThePlayer
    if player ~= nil and player.HUD ~= nil and player.HUD.eventannouncer ~= nil
        and player.HUD.eventannouncer.ShowNewAnnouncement ~= nil then
        player.HUD.eventannouncer:ShowNewAnnouncement(tostring(msg), { 1, 1, 1, 1 }, "default")
    else
        print("[CCBP] " .. tostring(msg))
    end
end
UI.OnToast = UI.Toast

local function MakeButton(parent, x, y, text, onclick, scale)
    local btn = parent:AddChild(ImageButton(BUTTON, BTN_NORMAL, BTN_HOVER, BTN_DISABLED, BTN_DOWN))
    btn:SetPosition(x, y)
    if scale ~= nil then
        btn:SetScale(scale, scale, 1)
    end
    btn:SetText(text)
    if btn.SetTextSize ~= nil then
        btn:SetTextSize(20)
    end
    btn:SetOnClick(onclick)
    return btn
end

-- ==================== 蓝图库浏览器 ====================

local Browser = Class(Screen, function(self, cannon_uid)
    Screen._ctor(self, "CCBP_Browser")
    self.cannon_uid = cannon_uid
    self.entries = nil
    self.page = 0
    self:Build()
    self:Refresh()
end)

function Browser:Build()
    self.black = self:AddChild(Image("images/global.xml", "square.tex"))
    self.black:SetSize(RESOLUTION_X, RESOLUTION_Y)
    self.black:SetTintColour(0, 0, 0, 0.5)

    self.panel = self:AddChild(Image("images/global.xml", "square.tex"))
    self.panel:SetSize(740, 620)
    self.panel:SetTintColour(0.12, 0.12, 0.15, 0.97)

    self.title = self:AddChild(Text(DEFAULTFONT, 36, "蓝图库"))
    self.title:SetPosition(0, 268)

    self.subtitle = self:AddChild(Text(DEFAULTFONT, 20, "加载中…"))
    self.subtitle:SetPosition(0, 232)

    self.rows = {}
    for i = 1, ROWS do
        local y = 184 - (i - 1) * 44
        local name = self:AddChild(Text(DEFAULTFONT, 22, ""))
        name:SetPosition(-120, y)
        local burn = MakeButton(self, 250, y, "刻录蓝图", function()
            self:OnBurn(i)
        end, 0.55)
        self.rows[i] = { name = name, burn = burn }
    end

    self.page_prev = MakeButton(self, -290, -248, "上一页", function()
        if self.page > 0 then
            self.page = self.page - 1
            self:Refresh()
        end
    end, 0.5)

    self.page_next = MakeButton(self, -185, -248, "下一页", function()
        self.page = self.page + 1
        self:Refresh()
    end, 0.5)

    self.reload = MakeButton(self, -80, -248, "重读JSON", function()
        SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "ReloadStore"))
    end, 0.5)

    self.canceljob = MakeButton(self, 25, -248, "取消施工", function()
        print("[CCBP] UI请求取消施工: " .. tostring(self.cannon_uid))
        SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "CancelConstruction"), self.cannon_uid)
    end, 0.5)

    self.close = MakeButton(self, 130, -248, "关闭", function()
        UI.CloseBrowser()
    end, 0.5)

    self.entry_label = self:AddChild(Text(DEFAULTFONT, 18, "手动读取:"))
    self.entry_label:SetPosition(-295, -292)
    self.entry = self:AddChild(TextEdit(DEFAULTFONT, 20, ""))
    self.entry:SetPosition(-150, -292)
    if self.entry.SetRegionSize ~= nil then
        self.entry:SetRegionSize(230, 30)
    end
    -- 注意: TextEdit 的 OnTextEntered 回调只传字符串
    self.entry.OnTextEntered = function(str)
        self:LoadFile(str)
    end
    self.load_btn = MakeButton(self, 30, -292, "读取", function()
        self:LoadFile(self.entry:GetString())
    end, 0.5)

    self.hint = self:AddChild(Text(DEFAULTFONT, 16,
        "蓝图文件放在游戏目录 unsafedata/ 或本mod目录 blueprints/\n多张蓝图可在 unsafedata/ccbp_index.json 里列文件名"))
    self.hint:SetPosition(0, -272)
end

function Browser:OnList(list)
    self.entries = list or {}
    self.page = 0
    self:Refresh()
end

function Browser:Refresh()
    if self.entries == nil then
        self.subtitle:SetString("加载中…")
        for _, row in ipairs(self.rows) do
            row.name:SetString("")
            row.burn:Hide()
        end
        return
    end
    local n = #self.entries
    local pages = math.max(1, math.ceil(n / ROWS))
    if self.page >= pages then
        self.page = pages - 1
    end
    if self.page < 0 then
        self.page = 0
    end
    self.subtitle:SetString(string.format("共 %d 张蓝图 · 第 %d/%d 页 · 刻录需要莎草纸x1", n, self.page + 1, pages))
    for i, row in ipairs(self.rows) do
        local e = self.entries[self.page * ROWS + i]
        if e ~= nil then
            row.name:SetString(e.name .. "  (" .. e.count .. ")")
            row.burn:Show()
        else
            row.name:SetString("")
            row.burn:Hide()
        end
    end
end

function Browser:OnBurn(i)
    if self.entries == nil then
        return
    end
    local e = self.entries[self.page * ROWS + i]
    if e == nil then
        return
    end
    local inv = ThePlayer ~= nil and ThePlayer.replica ~= nil and ThePlayer.replica.inventory or nil
    if inv ~= nil and inv.Has ~= nil and not inv:Has("papyrus", 1) then
        UI.Toast("背包里没有莎草纸x1")
        return
    end
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "BurnBlueprint"), e.id)
end

function Browser:OnControl(control, down)
    if Screen._base.OnControl(self, control, down) then
        return true
    end
    if down and control == CONTROL_CANCEL then
        UI.CloseBrowser()
        return true
    end
    return false
end

function Browser:LoadFile(name)
    if type(name) ~= "string" then
        return
    end
    name = string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")
    if #name == 0 then
        UI.Toast("请先输入文件名")
        return
    end
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "LoadBlueprintFile"), name)
end

-- ==================== 施工确认面板 ====================

local Confirm = Class(Screen, function(self, bp, info)
    Screen._ctor(self, "CCBP_Confirm")
    self:Build(bp)
    self:SetInfo(info)
end)

function Confirm:Build(bp)
    self.panel = self:AddChild(Image("images/global.xml", "square.tex"))
    self.panel:SetSize(560, 280)
    self.panel:SetTintColour(0.12, 0.12, 0.15, 0.97)

    self.title = self:AddChild(Text(DEFAULTFONT, 30, "确认施工"))
    self.title:SetPosition(0, 108)

    self.name = self:AddChild(Text(DEFAULTFONT, 22, bp ~= nil and bp.name or "?"))
    self.name:SetPosition(0, 66)

    self.info = self:AddChild(Text(DEFAULTFONT, 20, ""))
    self.info:SetPosition(0, 20)

    self.help = self:AddChild(Text(DEFAULTFONT, 17,
        "WASD 微调位置 (Shift慢速) · Q/E 旋转 · 右键或按钮确认 · ESC 取消"))
    self.help:SetPosition(0, -34)

    MakeButton(self, -90, -95, "确认施工", function()
        if PlacementRef ~= nil then
            PlacementRef.SendConfirm()
        end
    end, 0.6)

    MakeButton(self, 90, -95, "取消", function()
        if PlacementRef ~= nil then
            PlacementRef.Exit()
        end
    end, 0.6)
end

function Confirm:SetInfo(info)
    if self.info ~= nil then
        self.info:SetString(info or "")
    end
end

-- ==================== 对外接口 ====================

function UI.CloseBrowser()
    if UI.browser ~= nil then
        local b = UI.browser
        UI.browser = nil
        pcall(function()
            TheFrontEnd:PopScreen(b)
        end)
    end
end

function UI.OnOpenBrowser(cannon_uid, cannon_name)
    print("[CCBP] 客户端收到OpenBrowser, uid=" .. tostring(cannon_uid))
    UI.CloseBrowser()
    UI.browser = Browser(cannon_uid, cannon_name)
    TheFrontEnd:PushScreen(UI.browser)
    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "RequestList"))
end

function UI.OnList(list)
    print("[CCBP] 客户端收到蓝图列表: " .. tostring(list ~= nil and #list or "nil") .. " 张")
    if UI.browser ~= nil then
        UI.browser:OnList(list)
    end
end

function UI.ShowConfirm(bp, info)
    UI.HideConfirm()
    UI.confirm = Confirm(bp, info)
    TheFrontEnd:PushScreen(UI.confirm)
end

function UI.HideConfirm()
    if UI.confirm ~= nil then
        local c = UI.confirm
        UI.confirm = nil
        pcall(function()
            TheFrontEnd:PopScreen(c)
        end)
    end
end

function UI.SetConfirmInfo(info)
    if UI.confirm ~= nil then
        UI.confirm:SetInfo(info)
    end
end

return UI
