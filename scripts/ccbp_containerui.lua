-- 货槽界面的"所需材料"面板 + [开始施工]按钮
-- 通过 AddClassPostConstruct("widgets/containerwidget", ContainerUI.Install) 挂载(见 modmain)
-- 布局: 左侧蓝图槽(自带标签) + 右侧材料/进度面板(深色衬底) + [开始施工]按钮
-- 数据: 大炮实体上的 net_mats(材料/进度) 与 net_ready(蓝图就绪) 两个 netvar
local CCBP = require "ccbp_config"
local Text = require "widgets/text"
local Widget = require "widgets/widget"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"

local BTN = "images/global_redux.xml"
local BTN_NORMAL = "button_carny_long_normal.tex"
local BTN_HOVER = "button_carny_long_hover.tex"
local BTN_DISABLED = "button_carny_long_disabled.tex"
local BTN_DOWN = "button_carny_long_down.tex"

local ContainerUI = {}

function ContainerUI.Install(self)
    local oldOpen = self.Open
    self.Open = function(self2, container, ...)
        oldOpen(self2, container, ...)
        if container ~= nil and container.prefab == "construction_cannon" and container.net_mats ~= nil then
            -- 蓝图槽位置(单槽, 由 modmain 参数给出)
            local ok, containers = pcall(require, "containers")
            local slot1 = ok and containers ~= nil and containers.params ~= nil
                and containers.params.ccbp_cannon ~= nil
                and containers.params.ccbp_cannon.widget ~= nil
                and containers.params.ccbp_cannon.widget.slotpos ~= nil
                and containers.params.ccbp_cannon.widget.slotpos[1] or nil
            local bp_x = (slot1 ~= nil) and slot1.x or -180
            local bp_y = (slot1 ~= nil) and slot1.y or 40
            local px = bp_x + 200 -- 材料面板x

            -- 蓝图槽标签
            local bplabel = self2:AddChild(Text(DEFAULTFONT, 20, "蓝图槽"))
            bplabel:SetPosition(bp_x, bp_y - 52)
            bplabel:SetColour(1, 0.9, 0.6, 1)
            self2.ccbp_bplabel = bplabel

            -- 材料面板(深色衬底)
            local txt = container.net_mats:value() or ""
            local lines = math.max(3, select(2, string.gsub(txt, "\n", "")) + 1)
            local top = bp_y + 110
            local bottom = bp_y - 130
            local right = px + 230
            local left = bp_x - 80

            local backing = self2:AddChild(Image("images/global.xml", "square.tex"))
            backing:SetSize(right - left, top - bottom)
            backing:SetPosition((left + right) / 2, (top + bottom) / 2)
            backing:SetTint(0.12, 0.12, 0.15, 0.92)

            local panel = self2:AddChild(Text(DEFAULTFONT, 24, txt))
            panel:SetPosition(px, 60)
            panel:SetHAlign(ANCHOR_LEFT)
            panel:SetColour(1, 0.95, 0.75, 1)
            self2.ccbp_panel = panel

            -- [开始施工]按钮
            local btnroot = self2:AddChild(Widget("ccbp_btnroot"))
            btnroot:SetPosition(px + 60, bottom + 55)
            local btn = btnroot:AddChild(ImageButton(BTN, BTN_NORMAL, BTN_HOVER, BTN_DISABLED, BTN_DOWN))
            btn:SetScale(0.65, 0.65, 1)
            btn:SetText("开始施工")
            if btn.SetTextSize ~= nil then
                btn:SetTextSize(22)
            end
            btn:SetOnClick(function()
                if container.net_uid ~= nil then
                    SendModRPCToServer(GetModRPC(CCBP.MOD_NS, "StartConstruction"), container.net_uid:value())
                end
            end)
            self2.ccbp_btn = btn

            -- netvar 变化 → 刷新
            self2.ccbp_ready_fn = function()
                if btn.inst ~= nil and btn.inst:IsValid() then
                    if container.net_ready ~= nil and container.net_ready:value() then
                        btn:Show()
                    else
                        btn:Hide()
                    end
                end
            end
            self2.ccbp_mats_fn = function()
                if panel.inst ~= nil and panel.inst:IsValid() then
                    panel:SetString(container.net_mats:value())
                end
            end
            container:ListenForEvent("ccbpmatsdirty", self2.ccbp_mats_fn)
            container:ListenForEvent("ccbpreadydirty", self2.ccbp_ready_fn)
            self2.ccbp_mats_fn()
            self2.ccbp_ready_fn()
        end
    end

    local oldClose = self.Close
    self.Close = function(self2, ...)
        if self2.ccbp_container ~= nil then
            if self2.ccbp_mats_fn ~= nil then
                self2.ccbp_container:RemoveEventCallback("ccbpmatsdirty", self2.ccbp_mats_fn)
            end
            if self2.ccbp_ready_fn ~= nil then
                self2.ccbp_container:RemoveEventCallback("ccbpreadydirty", self2.ccbp_ready_fn)
            end
        end
        for _, k in ipairs({ "ccbp_panel", "ccbp_bplabel", "ccbp_btn" }) do
            if self2[k] ~= nil then
                self2[k]:Kill()
                self2[k] = nil
            end
        end
        self2.ccbp_container = nil
        self2.ccbp_mats_fn = nil
        self2.ccbp_ready_fn = nil
        return oldClose(self2, ...)
    end
end

return ContainerUI
