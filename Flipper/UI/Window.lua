-- Main window: Flips (AH below vendor), Bags (best use), Crafts (recipe margins).
local _, ns = ...
local Window = {tab = "flips", offset = 0}
ns.Window = Window
local Money = ns.Money

local ROWS, ROW_HEIGHT, WIDTH = 14, 22, 560
local COLUMNS = {
    flips  = {"Item", "AH min", "Vendor", "Profit/ea", "Listed"},
    bags   = {"Item", "Best use", "Per unit", "Total", ""},
    crafts = {"Recipe", "Cost", "Value", "Profit", ""},
    recipes = {"Recipe for sale", "AH price", "Profit/craft", "Pays back", "Skill"},
}
local RECIPE_STATUS = {
    learnable = "|cff4ade80%d|r", skill = "|cfff87171%d|r", other = "|cff9ca3af%d|r", unverified = "|cfffbbf24%d?|r",
}
local COLUMN_X = {34, 250, 340, 430, 515}
local ACTION_TEXT = {ah = "|cff60a5faAuction|r", vendor = "Vendor", craft = "|cff4ade80Craft|r", none = "|cff9ca3af-|r"}
local STATUS = {
    idle = "Open the AH and press Scan.", browse = "Browsing the auction house...",
    evaluating = "Checking vendor prices...", closed = "Open the auction house to scan.",
    unsupported = "This client has no modern AH API.", interrupted = "Scan interrupted by another search.",
    failed = "The AH refused the browse request. Try again.", timeout = "The AH stopped answering. Try again.",
    stopped = "Stopped.",
}

local function qualityName(row)
    local color = row.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
    return color and color.hex and (color.hex .. row.name .. "|r") or row.name
end

local function craftRows()
    local rows = {}
    for _, recipe in ns.Recipes.All() do
        local margin = ns.Logic.CraftMargin(recipe, ns.Prices.AH, ns.AH_CUT)
        local name, _, quality, icon = ns.Compat.ItemInfo(recipe.output)
        rows[#rows + 1] = {name = recipe.name or name or "?", quality = quality, icon = icon,
            itemID = recipe.output, margin = margin}
    end
    table.sort(rows, function(a, b)
        local pa, pb = a.margin.profit, b.margin.profit
        if (pa ~= nil) ~= (pb ~= nil) then return pa ~= nil end
        if pa and pb and pa ~= pb then return pa > pb end
        return a.name < b.name
    end)
    return rows
end

function Window.Data()
    if Window.tab == "flips" then return ns.Scanner.rows end
    if Window.tab == "bags" then return ns.Bags.Rows() end
    if Window.tab == "recipes" then return ns.RecipeShop.Rows() end
    return craftRows()
end

local function fill(row, data)
    row.data = data
    row.icon:SetTexture(data.icon or 134400)
    local cells = row.cells
    for _, cell in ipairs(cells) do cell:SetText("") end
    if Window.tab == "flips" then
        cells[1]:SetText(qualityName(data))
        cells[2]:SetText(Money.Format(data.minPrice))
        cells[3]:SetText(Money.Format(data.vendor))
        cells[4]:SetText("|cff4ade80" .. Money.Format(data.profit) .. "|r")
        cells[5]:SetText(tostring(data.quantity))
    elseif Window.tab == "bags" then
        cells[1]:SetText(qualityName(data) .. " x" .. data.count)
        local advice = data.advice
        cells[2]:SetText(advice.action == "craft" and (ACTION_TEXT.craft .. ": " .. advice.craftName) or ACTION_TEXT[advice.action])
        cells[3]:SetText(Money.Format(advice.perUnit))
        cells[4]:SetText(Money.Format(data.total))
    elseif Window.tab == "recipes" then
        cells[1]:SetText(qualityName(data))
        cells[2]:SetText(Money.Format(data.price))
        cells[3]:SetText("|cff4ade80" .. Money.Format(data.profit) .. "|r")
        cells[4]:SetText(data.payback and (data.payback .. (data.payback == 1 and " craft" or " crafts")) or "")
        cells[5]:SetText(string.format(RECIPE_STATUS[data.status], data.skill))
    else
        local m = data.margin
        cells[1]:SetText(qualityName(data))
        cells[2]:SetText(#m.missing > 0 and "|cff9ca3afno price|r" or Money.Format(m.cost))
        cells[3]:SetText(m.value and Money.Format(m.value) or "|cff9ca3afno price|r")
        if m.profit then
            cells[4]:SetText((m.profit >= 0 and "|cff4ade80" or "|cfff87171") .. Money.FormatSigned(m.profit) .. "|r")
        end
    end
    row:Show()
end

function Window.Refresh()
    local frame = Window.frame
    if not frame or not frame:IsShown() then return end
    local data = Window.Data()
    Window.offset = math.max(0, math.min(Window.offset, #data - ROWS))
    for i, header in ipairs(frame.headers) do header:SetText(COLUMNS[Window.tab][i]) end
    for i, row in ipairs(frame.rows) do
        local entry = data[i + Window.offset]
        if entry then fill(row, entry) else row:Hide() end
    end
    for key, button in pairs(frame.tabs) do button:SetEnabled(key ~= Window.tab) end
    local status
    if Window.tab == "flips" then
        local s = ns.Scanner
        status = STATUS[s.state] or ""
        if s.state == "done" then
            status = string.format("%d flips from %d items on the AH.", #s.rows, s.total)
            if s.deferred > 0 then status = status .. string.format(" %d items had no data yet; scan again.", s.deferred) end
        end
        frame.scan:SetEnabled(ns.Compat.AuctionHouseOpen() and not s.running)
        frame.scan:Show()
    elseif Window.tab == "recipes" then
        status = #data .. " money-making recipes you don't know" .. (ns.RecipeShop.showAll and " (all professions)" or "")
            .. ". Skill: |cff4ade80can learn|r |cfff87171need skill|r |cfffbbf24open profession once|r"
        frame.scan:Hide()
    elseif Window.tab == "crafts" then
        status = #data == 0 and "Open each profession window once to teach Flipper your recipes." or (#data .. " recipes, AH prices from " .. (ns.Prices.Source() or "nothing"))
        frame.scan:Hide()
    else
        status = "Prices from " .. (ns.Prices.Source() or "nothing (install Auctionator)") .. ", after the 5% AH cut."
        frame.scan:Hide()
    end
    frame.status:SetText(status)
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 24, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 12, -64 - (index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", 8, 0)
    row.cells = {}
    for i, x in ipairs(COLUMN_X) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", x, 0)
        cell:SetWidth(i == 1 and 210 or 88)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        row.cells[i] = cell
    end
    row:SetScript("OnEnter", function(self)
        if not self.data or not self.data.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.data.itemID)
        if Window.tab == "flips" or Window.tab == "recipes" then
            GameTooltip:AddLine("Click: open in Auctionator to buy", 0.3, 0.9, 0.5)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if (Window.tab == "flips" or Window.tab == "recipes") and self.data then ns.Scanner.OpenInAuctionator(self.data) end
    end)
    return row
end

function Window.Create()
    if Window.frame then return Window.frame end
    local frame = CreateFrame("Frame", "FlipperFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, 64 + ROWS * ROW_HEIGHT + 34)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "FlipperFrame")
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("Flipper")

    frame.tabs = {}
    for i, key in ipairs({"flips", "bags", "crafts", "recipes"}) do
        local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        tab:SetSize(80, 22)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 84, -28)
        tab:SetText(key:sub(1, 1):upper() .. key:sub(2))
        tab:SetScript("OnClick", function() Window.tab, Window.offset = key, 0; Window.Refresh() end)
        frame.tabs[key] = tab
    end
    frame.scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.scan:SetSize(90, 22)
    frame.scan:SetPoint("TOPRIGHT", -12, -28)
    frame.scan:SetText("Scan")
    frame.scan:SetScript("OnClick", function() ns.Scanner.Start() end)

    frame.headers = {}
    for i, x in ipairs(COLUMN_X) do
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", 12 + x, -52)
        frame.headers[i] = header
    end
    frame.rows = {}
    for i = 1, ROWS do frame.rows[i] = createRow(frame, i) end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        Window.offset = math.max(0, Window.offset - delta * 3)
        Window.Refresh()
    end)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.status:SetPoint("BOTTOMLEFT", 14, 12)
    frame.status:SetPoint("BOTTOMRIGHT", -14, 12)
    frame.status:SetJustifyH("LEFT")
    frame:SetScript("OnShow", Window.Refresh)
    Window.frame = frame
    return frame
end

function Window.Toggle(tab)
    local frame = Window.Create()
    if tab then
        Window.tab, Window.offset = tab, 0
        frame:Show()
        Window.Refresh()
    elseif frame:IsShown() then frame:Hide()
    else frame:Show() end
end
