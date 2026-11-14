-- Esc > Options > AddOns > Flipper: every setting on one page. Reads and writes through
-- ns.Settings, like the minimap menu. Registered at PLAYER_LOGIN; if the client's Settings
-- API isn't there, the minimap menu and slash commands still cover every setting.
local _, ns = ...
local Options = {}
ns.Options = Options

local GOLD, GREY = {1, 0.82, 0}, {0.61, 0.64, 0.69}
local LEFT = 16

local function label(parent, text, size, color)
    local font = parent:CreateFontString(nil, "ARTWORK", size == "big" and "GameFontNormalLarge" or "GameFontHighlight")
    font:SetText(text)
    font:SetJustifyH("LEFT")
    if color then font:SetTextColor(color[1], color[2], color[3]) end
    return font
end

local function hoverTip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function build(panel)
    local controls = {}
    panel.controls = controls
    local y = -16
    local function heading(text)
        local h = label(panel, text, nil, GOLD)
        h:SetPoint("TOPLEFT", LEFT, y)
        y = y - 22
    end
    local function toggle(key)
        local setting = ns.Settings.BY_KEY[key]
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetSize(26, 26)
        box:SetPoint("TOPLEFT", LEFT, y)
        local text = label(box, setting.label)
        text:SetPoint("LEFT", box, "RIGHT", 4, 0)
        box:SetScript("OnClick", function(self) ns.Settings.Set(key, self:GetChecked()) end)
        hoverTip(box, setting.tip)
        controls[key] = function() box:SetChecked(ns.Settings.Get(key) and true or false) end
        y = y - 28
    end
    local function choices(key, extra)
        local setting = ns.Settings.BY_KEY[key]
        local caption = label(panel, setting.label)
        caption:SetPoint("TOPLEFT", LEFT + 4, y)
        y = y - 20
        local buttons, x = {}, LEFT + 4
        for _, value in ipairs(setting.presets) do
            local b = button(panel, (ns.Settings.Format(key, value):gsub("|T.-|t", "")), 64, function() ns.Settings.Set(key, value) end)
            b:SetPoint("TOPLEFT", x, y)
            hoverTip(b, setting.tip)
            buttons[value] = b
            x = x + 68
        end
        if extra then extra(x, y) end
        controls[key] = function()
            local current = ns.Settings.Get(key)
            for value, b in pairs(buttons) do
                if value == current then b:LockHighlight() else b:UnlockHighlight() end
            end
        end
        y = y - 32
    end

    local title = label(panel, "Flipper", "big")
    title:SetPoint("TOPLEFT", LEFT, y)
    y = y - 22
    local sub = label(panel, "The same settings are on the minimap button's right-click menu.", nil, GREY)
    sub:SetPoint("TOPLEFT", LEFT, y)
    y = y - 30

    heading("Scanning and tooltips")
    toggle("autoQuickScan")
    toggle("tooltip")
    y = y - 8

    heading("What's worth showing")
    choices("minFlipProfit", function(x, rowY)
        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetSize(90, 20)
        box:SetPoint("TOPLEFT", x + 8, rowY - 1)
        box:SetAutoFocus(false)
        local current = label(panel, "")
        current:SetPoint("LEFT", box, "RIGHT", 8, 0)
        local function show() current:SetText(ns.Money.Format(ns.Settings.Get("minFlipProfit"))) end
        box:SetScript("OnEnterPressed", function(self)
            local copper = ns.Money.Parse(self:GetText())
            if copper then ns.Settings.Set("minFlipProfit", copper) else ns.Print("amounts look like 50c, 2s 50c or 1g") end
            self:SetText("")
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
        hoverTip(box, "Type an amount such as 2s 50c or 1g, then press Enter.")
        controls.minFlipProfitText = show
    end)
    choices("dealRatio")
    y = y - 4

    heading("Minimap button")
    toggle("showMinimap")
    toggle("lockMinimap")
    y = y - 8

    heading("Window")
    local recipes = button(panel, "", 220, function()
        ns.RecipeShop.NextFilter()
        ns.RecipeShop.Invalidate()
        ns.Launcher.Changed()
    end)
    recipes:SetPoint("TOPLEFT", LEFT + 4, y)
    hoverTip(recipes, "Which recipes the Recipes tab lists. Click for the next choice.")
    controls.recipes = function() recipes:SetText("Recipes tab: " .. ns.RecipeShop.FilterLabel()) end
    local reset = button(panel, "Reset window position", 170, function() ns.Window.ResetGeometry() end)
    reset:SetPoint("LEFT", recipes, "RIGHT", 8, 0)
    local open = button(panel, "Open Flipper", 120, function() ns.Window.Toggle() end)
    open:SetPoint("LEFT", reset, "RIGHT", 8, 0)
end

function Options.Refresh()
    local panel = Options.panel
    if not panel or not panel.controls or not panel:IsVisible() then return end
    for _, update in pairs(panel.controls) do update() end
end

function Options.Register()
    if Options.panel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Flipper"
    panel:Hide()
    panel:SetScript("OnShow", function(self)
        if not self.controls then build(self) end
        Options.Refresh()
    end)
    Options.panel = panel
    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Flipper")
        if ok and category and pcall(Settings.RegisterAddOnCategory, category) then
            Options.category = category
        end
    end
end

-- Opens the page. False when the client has no settings window to open it in.
function Options.Open()
    Options.Register()
    local category = Options.category
    if not category or not Settings or type(Settings.OpenToCategory) ~= "function" then return false end
    if InCombatLockdown and InCombatLockdown() then ns.Print("settings open after combat"); return true end
    local id = category.GetID and category:GetID() or category.ID
    return pcall(Settings.OpenToCategory, id) and true or false
end
