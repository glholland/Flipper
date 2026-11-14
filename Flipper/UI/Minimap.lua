-- The minimap button and the addon-menu entry: left click opens Flipper, right click opens
-- the settings menu, Shift-click quick scans, drag moves it around the minimap.
-- Flipper ships no libraries. If another addon has loaded LibDBIcon (Questie, Details,
-- Journalator and others embed it), the button is registered there, so button collectors
-- such as Leatrix Plus and square-minimap addons handle it like every other. Otherwise
-- Flipper draws a plain button of its own.
local addonName, ns = ...
local Launcher = {}
ns.Launcher = Launcher

local NAME = "Flipper"
local ICON = 133784
local GREY, WHITE = "|cff9ca3af", "|cffffffff"

local function db()
    FlipperDB.minimap = FlipperDB.minimap or {}
    return FlipperDB.minimap
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------

local function quickScan()
    if not ns.Compat.AuctionHouseOpen() then ns.Print("open the auction house to scan"); return end
    ns.Scanner.Start()
end

local function fullScan()
    if not ns.Compat.AuctionHouseOpen() then ns.Print("open the auction house to scan"); return end
    ns.Market.Start()
end

function Launcher.OnClick(owner, button)
    if button == "RightButton" then Launcher.OpenMenu(owner)
    elseif IsShiftKeyDown() then quickScan()
    else ns.Window.Toggle() end
end

------------------------------------------------------------------------
-- Hover tooltip
------------------------------------------------------------------------

local function age(seconds)
    if seconds < 3600 then return math.max(0, math.floor(seconds / 60)) .. "m" end
    if seconds < 172800 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

local function bestDeal()
    local ok, rows = pcall(ns.Deals.Rows)
    local best
    for _, row in ipairs(ok and rows or {}) do
        if not best or row.profit > best.profit then best = row end
    end
    return best
end

function Launcher.Tooltip(tip)
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    tip:AddDoubleLine("Flipper", version and (GREY .. version .. "|r") or "")
    local fraction, label = ns.Market.Progress()
    if not label then fraction, label = ns.Scanner.Progress() end
    if label then
        tip:AddLine(label .. (fraction and string.format(" (%d%%)", fraction * 100) or ""), 1, 1, 1)
    else
        local now = time()
        local full, summary = ns.Market.AuctionatorTimes()
        local priced = math.max(full or 0, summary or 0, ns.Market.LastFullScan() or 0, ns.Scanner.doneAt or 0)
        local sales = ns.Market.LastFullScan()
        tip:AddDoubleLine("Prices", priced > 0 and (age(now - priced) .. " old") or "no scans yet", 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Sales estimates", sales and (age(now - sales) .. " old") or "need a full scan", 1, 1, 1, 1, 1, 1)
        local wait = ns.Market.CooldownLeft()
        tip:AddDoubleLine("Full scan", wait > 0 and string.format("ready in %d:%02d", math.floor(wait / 60), wait % 60)
            or "ready", 1, 1, 1, 1, 1, 1)
        local deal = bestDeal()
        if deal then tip:AddDoubleLine("Best deal", deal.name .. "  " .. ns.Money.Format(deal.profit), 1, 1, 1, 0.29, 0.87, 0.5) end
    end
    tip:AddLine(" ")
    tip:AddLine(GREY .. "Click|r " .. WHITE .. "open Flipper|r   " .. GREY .. "Right-click|r " .. WHITE .. "settings|r")
    tip:AddLine(GREY .. "Shift-click|r " .. WHITE .. "quick scan|r   " .. GREY .. "Drag|r " .. WHITE .. "move|r")
end

------------------------------------------------------------------------
-- Settings menu (right click)
------------------------------------------------------------------------

local function disable(element, why)
    if element and element.SetEnabled then element:SetEnabled(false) end
    if why and element and element.SetTooltip then
        element:SetTooltip(function(tip) tip:AddLine(why, 1, 1, 1, true) end)
    end
end

local function addToggle(root, key)
    local setting = ns.Settings.BY_KEY[key]
    root:CreateCheckbox(setting.label, function() return ns.Settings.Get(key) end,
        function() ns.Settings.Toggle(key) end)
end

local function addChoices(root, key)
    local setting = ns.Settings.BY_KEY[key]
    local sub = root:CreateButton(setting.label .. ": " .. ns.Settings.Format(key))
    for _, value in ipairs(setting.presets) do
        sub:CreateRadio(ns.Settings.Format(key, value), function() return ns.Settings.Get(key) == value end,
            function() ns.Settings.Set(key, value) end)
    end
    sub:CreateButton("Other amount...", function() Launcher.OpenOptions() end)
end

local function build(_, root)
    root:CreateTitle("Flipper")
    root:CreateButton("Open Flipper", function() ns.Window.Toggle() end)
    local open = ns.Compat.AuctionHouseOpen()
    local busy = ns.Window.ScanBusy()
    local quick = root:CreateButton("Quick scan", quickScan)
    local wait = ns.Market.CooldownLeft()
    local full = root:CreateButton(wait > 0 and string.format("Full scan (%d:%02d)", math.floor(wait / 60), wait % 60)
        or "Full scan", fullScan)
    if not open then disable(quick, "Open the auction house first."); disable(full, "Open the auction house first.")
    elseif busy then disable(quick, "A scan is running."); disable(full, "A scan is running.")
    elseif wait > 0 then disable(full, "The server allows one full scan per 15 minutes.") end
    root:CreateDivider()
    addToggle(root, "autoQuickScan")
    addToggle(root, "tooltip")
    addChoices(root, "minFlipProfit")
    addChoices(root, "dealRatio")
    local recipes = root:CreateButton("Recipes tab shows: " .. ns.RecipeShop.FilterLabel())
    recipes:CreateButton("Next choice", function() ns.RecipeShop.NextFilter(); ns.RecipeShop.Invalidate(); Launcher.Changed() end)
    recipes:CreateButton("Every profession", function() ns.RecipeShop.SetEverything(); ns.RecipeShop.Invalidate(); Launcher.Changed() end)
    root:CreateDivider()
    addToggle(root, "showMinimap")
    addToggle(root, "lockMinimap")
    root:CreateButton("Reset window position", function() ns.Window.ResetGeometry() end)
    root:CreateButton("All settings...", function() Launcher.OpenOptions() end)
end

function Launcher.OpenMenu(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner or UIParent, build)
    else
        Launcher.OpenOptions()
    end
end

function Launcher.OpenOptions()
    if ns.Options and ns.Options.Open() then return end
    ns.Print("settings: /flip auto | /flip tooltip | /flip minprofit <copper> | /flip minimap")
end

------------------------------------------------------------------------
-- The button
------------------------------------------------------------------------

local function placeOwn(button)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local x, y = ns.Settings.RimOffset(db().minimapPos, Minimap:GetWidth() / 2 + 5, shape)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragging(button)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    db().minimapPos = ns.Settings.AngleFrom(cx / scale - mx, cy / scale - my)
    placeOwn(button)
end

-- A minimap button in the usual style, for when LibDBIcon isn't loaded. No global name.
local function createOwn()
    local button = CreateFrame("Button", nil, Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(50, 50)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -6)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self, mouse) Launcher.OnClick(self, mouse) end)
    button:SetScript("OnDragStart", function(self)
        if db().lock then return end
        GameTooltip:Hide()
        self:SetScript("OnUpdate", dragging)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        if self:GetScript("OnUpdate") then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Launcher.Tooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeOwn(button)
    return button
end

-- Called at PLAYER_LOGIN, when every addon (and any LibDBIcon) has loaded.
function Launcher.Create()
    if Launcher.created or not Minimap then return end
    Launcher.created = true
    local stub = LibStub
    local broker = stub and stub.GetLibrary and stub:GetLibrary("LibDataBroker-1.1", true)
    local icons = stub and stub.GetLibrary and stub:GetLibrary("LibDBIcon-1.0", true)
    if broker and icons then
        local object = broker:GetDataObjectByName(NAME) or broker:NewDataObject(NAME, {
            type = "launcher", text = NAME, icon = ICON,
            OnClick = function(frame, mouse) Launcher.OnClick(frame, mouse) end,
            OnTooltipShow = function(tip) Launcher.Tooltip(tip) end,
        })
        local ok = object and pcall(icons.Register, icons, NAME, object, db())
        if ok then Launcher.icons = icons end
    end
    if not Launcher.icons then Launcher.button = createOwn() end
    Launcher.Apply()
end

-- Shows, hides, locks or unlocks the button to match the settings.
function Launcher.Apply()
    local saved = db()
    if Launcher.icons then
        if saved.hide then Launcher.icons:Hide(NAME) else Launcher.icons:Show(NAME) end
        if saved.lock then Launcher.icons:Lock(NAME) else Launcher.icons:Unlock(NAME) end
    elseif Launcher.button then
        Launcher.button:SetShown(not saved.hide)
        placeOwn(Launcher.button)
    end
end

-- After any settings change: everything that shows a setting catches up.
function Launcher.Changed(key)
    if key == "showMinimap" or key == "lockMinimap" then Launcher.Apply() end
    if key == "showMinimap" and db().hide then
        ns.Print("minimap button hidden: the addon menu on the minimap or /flip minimap brings it back")
    end
    if key == "minFlipProfit" or key == "dealRatio" then
        if ns.History then ns.History.Invalidate() end
        if ns.Vendors then ns.Vendors.Invalidate() end
    end
    if ns.Options then ns.Options.Refresh() end
    if ns.Window.IsVisible() then ns.Window.Refresh() end
end

------------------------------------------------------------------------
-- Addon menu (the minimap's addon compartment). The TOC names these three globals.
------------------------------------------------------------------------

function Flipper_OnAddonCompartmentClick(_, mouse)
    Launcher.OnClick(UIParent, mouse)
end
function Flipper_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    Launcher.Tooltip(GameTooltip)
    GameTooltip:Show()
end
function Flipper_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
