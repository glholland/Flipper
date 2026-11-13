-- Main window: Flips (AH below vendor), Bags (best use), Crafts (recipe margins), Recipes (to buy).
-- Resizable (drag the bottom-right corner); click a column header to sort, again to reverse.
local _, ns = ...
local Window = {tab = "flips", offset = 0}
ns.Window = Window
local Money = ns.Money

local ROW_HEIGHT, HEADER_Y, TOP_ROWS_Y = 22, -52, -66
local VALUE_WIDTH, ICON_SPACE, PAD = 92, 34, 12
local MIN_W, MIN_H, MAX_W, MAX_H = 680, 260, 1400, 1000
local DEFAULT_W, DEFAULT_H = 760, 440
local TAB_ORDER = {"flips", "vendor", "bags", "crafts", "recipes", "history"}
local TAB_LABEL = {flips = "AH flips", vendor = "Vendor", bags = "Bags", crafts = "Crafts", recipes = "Recipes",
    history = "History"}

local ACTION_TEXT = {ah = "|cff60a5faAuction|r", vendor = "Vendor", craft = "|cff4ade80Craft|r", none = "|cff9ca3af-|r"}
local RECIPE_STATUS = {
    learnable = "|cff4ade80%d|r", skill = "|cfff87171%d|r", other = "|cff9ca3af%d|r", unverified = "|cfffbbf24%d?|r",
}
local STATUS = {
    idle = "Open the AH and press Scan.", browse = "Browsing the auction house...",
    evaluating = "Checking vendor prices...", closed = "Open the auction house to scan.",
    unsupported = "This client has no modern AH API.", interrupted = "Scan interrupted by another search.",
    failed = "The AH refused the browse request. Try again.", timeout = "The AH stopped answering. Try again.",
    stopped = "Stopped.",
}
local GREY_NO_PRICE = "|cff9ca3afno price|r"

local function qualityName(row)
    local color = row.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
    return color and color.hex and (color.hex .. row.name .. "|r") or row.name
end
local function green(text) return "|cff4ade80" .. text .. "|r" end
local function signed(copper)
    if not copper then return "" end
    return (copper >= 0 and "|cff4ade80" or "|cfff87171") .. Money.FormatSigned(copper) .. "|r"
end

-- Each column: header label, sort value, cell text. Column 1 is the name column.
local TABS = {
    flips = {
        default = {4, true},
        {"Item", function(r) return r.name end, function(r) return qualityName(r) end},
        {"AH min", function(r) return r.minPrice end, function(r) return Money.Format(r.minPrice) end},
        {"Vendor", function(r) return r.vendor end, function(r) return Money.Format(r.vendor) end},
        {"Profit/ea", function(r) return r.profit end, function(r) return green(Money.Format(r.profit)) end},
        {"Listed", function(r) return r.quantity end, function(r) return tostring(r.quantity) end, 64},
        {"Sold/day", function(r) return (ns.Market.Rate(r.itemID)) end,
            function(r) return ns.Market.FormatRate((ns.Market.Rate(r.itemID))) end, 70},
    },
    bags = {
        default = {4, true},
        {"Item", function(r) return r.name end, function(r) return qualityName(r) .. " x" .. r.count end},
        {"Best use", function(r) return r.advice.action end, function(r)
            local a = r.advice
            return a.action == "craft" and (ACTION_TEXT.craft .. ": " .. a.craftName) or ACTION_TEXT[a.action]
        end},
        {"Per unit", function(r) return r.advice.perUnit end, function(r) return Money.Format(r.advice.perUnit) end},
        {"Total", function(r) return r.total end, function(r) return Money.Format(r.total) end},
    },
    crafts = {
        default = {4, true},
        {"Recipe", function(r) return r.name end, function(r) return qualityName(r) end},
        {"Cost", function(r) return #r.margin.missing == 0 and r.margin.cost or nil end, function(r)
            return #r.margin.missing > 0 and GREY_NO_PRICE or Money.Format(r.margin.cost)
        end},
        {"Value", function(r) return r.margin.value end, function(r)
            return r.margin.value and Money.Format(r.margin.value) or GREY_NO_PRICE
        end},
        {"Profit", function(r) return r.margin.profit end, function(r) return signed(r.margin.profit) end},
    },
    vendor = {
        default = {4, true},
        {"Item", function(r) return r.name end, function(r)
            return qualityName(r) .. (r.limited and " |cfffbbf24(limited)|r" or "")
        end},
        {"Vendor", function(r) return r.buy end, function(r)
            return Money.Format(r.buy) .. (r.source == "data" and "|cff9ca3af*|r" or "")
        end},
        {"AH fair", function(r) return r.fair end, function(r) return Money.Format(r.fair) end},
        {"Profit/ea", function(r) return r.profit end, function(r) return green(Money.Format(r.profit)) end},
        {"Where to buy", function(r) return r.where end, function(r) return r.where end, 220},
        {"Sold/day", function(r) return (ns.Market.Rate(r.itemID)) end,
            function(r) return ns.Market.FormatRate((ns.Market.Rate(r.itemID))) end, 70},
    },
    recipes = {
        sortKey = "recipes:v2",
        default = {4, true},
        {"Recipe for sale", function(r) return r.name end, function(r) return qualityName(r) end},
        {"Vendor", function(r) return r.vendor end, function(r)
            return r.vendor and Money.Format(r.vendor) or "|cff9ca3afDrop|r"
        end},
        {"AH price", function(r) return r.price end, function(r) return Money.Format(r.price) end},
        {"Profit/craft", function(r) return r.profit end, function(r) return green(Money.Format(r.profit)) end},
        {"Pays back", function(r) return r.payback end, function(r)
            return r.payback and (r.payback .. (r.payback == 1 and " craft" or " crafts")) or ""
        end},
        {"Skill", function(r) return r.skill end, function(r) return string.format(RECIPE_STATUS[r.status], r.skill) end, 60},
        {"Sells/day", function(r) return r.outputRate end, function(r) return ns.Market.FormatRate(r.outputRate) end, 70},
    },
}
local function count(v) return v and tostring(v) or "|cff9ca3af-|r" end

-- History: a summary of every watched item, or day by day for Window.historyItem.
TABS.history = {
    default = {2, true},
    {"Item (click for its history)", function(r) return r.name end, function(r) return qualityName(r) end},
    {"Sold", function(r) return r.sold end, function(r) return green(r.sold) end, 64},
    {"Expired", function(r) return r.expired end, function(r) return tostring(r.expired) end, 64},
    {"Relisted", function(r) return r.cancelled end, function(r) return tostring(r.cancelled) end, 64},
    {"Sell-through", function(r) return r.through end, function(r)
        return string.format("%d%%", math.floor(r.through * 100 + 0.5))
    end, 80},
    {"Sold/day", function(r) return r.perDay end, function(r) return ns.Market.FormatRate(r.perDay) end, 70},
}
TABS.historyItem = {
    sortKey = "historyItem",
    default = {1, true},
    barColumn = 2,
    {"Day", function(r) return r.day end, function(r) return r.name end},
    {"Lowest", function(r) return r.low end, function(r) return r.low and Money.Format(r.low) or count(nil) end, 110},
    {"Highest", function(r) return r.high end, function(r) return r.high and Money.Format(r.high) or count(nil) end, 100},
    {"Listed", function(r) return r.listed end, function(r) return count(r.listed) end, 60},
    {"Sold", function(r) return r.sold end, function(r) return r.sold and green(r.sold) or count(nil) end, 56},
    {"Expired", function(r) return r.expired end, function(r) return count(r.expired) end, 60},
    {"Relisted", function(r) return r.cancelled end, function(r) return count(r.cancelled) end, 64},
}

function Window.Spec()
    if Window.tab == "history" and Window.historyItem then return TABS.historyItem end
    return TABS[Window.tab]
end

-- Opens the History tab on one item (row right-click, /flip history <item>, shift-click a link).
function Window.ShowHistory(itemID)
    Window.historyItem = ns.IsNumber(itemID) and itemID or nil
    Window.Toggle("history")
end

local MAX_COLUMNS = 7
local MARKET_STATUS = {
    replicating = "Full scan: waiting for the AH...", reading = "Full scan: reading listings...",
    timeout = "Full scan: the AH didn't answer. Try again later.", unsupported = "Full scans aren't available on this client.",
}

local function craftRows()
    local rows = {}
    for _, recipe in ns.Recipes.All() do
        local name, _, quality, icon = ns.Compat.ItemInfo(recipe.output)
        rows[#rows + 1] = {name = recipe.name or name or "?", quality = quality, icon = icon,
            itemID = recipe.output, margin = ns.Logic.CraftMargin(recipe, ns.Prices.AH, ns.AH_CUT, ns.Prices.Fair)}
    end
    return rows
end

local function sortState()
    local saved = FlipperDB.window.sort or {}
    FlipperDB.window.sort = saved
    -- sortKey changes when a tab's columns change, so an old saved column index can't point
    -- at the wrong column.
    local key = Window.Spec().sortKey or Window.tab
    local state = saved[key]
    if not state then
        local default = Window.Spec().default
        state = {column = default[1], descending = default[2]}
        saved[key] = state
    end
    return state
end

function Window.Data()
    local rows
    if Window.tab == "flips" then
        rows = {}
        for i, row in ipairs(ns.Scanner.rows) do rows[i] = row end  -- don't reorder the scanner's own list
    elseif Window.tab == "vendor" then
        rows = {}
        for i, row in ipairs(ns.Vendors.FlipRows()) do rows[i] = row end
    elseif Window.tab == "bags" then rows = ns.Bags.Rows()
    elseif Window.tab == "recipes" then rows = ns.RecipeShop.Rows()
    elseif Window.tab == "history" then
        rows = Window.historyItem and ns.History.ItemDays(Window.historyItem) or ns.History.Summary()
    else rows = craftRows() end
    local state = sortState()
    local column = Window.Spec()[state.column]
    if column then ns.Logic.SortRows(rows, column[2], state.descending) end
    return rows
end

-- Positions headers and cells for the current width: value columns have a fixed width
-- from the right edge, the name column takes whatever is left.
local function layout()
    local frame = Window.frame
    local width = frame:GetWidth()
    local columns = Window.Spec()
    local count = #columns
    local widths, fixed = {}, 0
    for i = 2, count do widths[i] = columns[i][4] or VALUE_WIDTH; fixed = fixed + widths[i] end
    widths[1] = math.max(120, width - 2 * PAD - ICON_SPACE - fixed)
    local x = {ICON_SPACE}
    for i = 2, count do x[i] = x[i - 1] + widths[i - 1] end
    for i, header in ipairs(frame.headers) do
        header:ClearAllPoints()
        if i <= count then
            header:SetPoint("TOPLEFT", PAD + x[i], HEADER_Y)
            header:SetWidth(widths[i])
            header:Show()
        else header:Hide() end
    end
    -- Enough rows to fill the height.
    -- Bottom reserve: status line + progress bar.
    local visible = math.max(1, math.floor((frame:GetHeight() + TOP_ROWS_Y - 50) / ROW_HEIGHT))
    for i = #frame.rows + 1, visible do frame.rows[i] = Window.CreateRow(frame, i) end
    for i, row in ipairs(frame.rows) do
        row:SetWidth(width - 2 * PAD)
        for c, cell in ipairs(row.cells) do
            cell:ClearAllPoints()
            if c <= count then
                cell:SetPoint("LEFT", x[c], 0)
                cell:SetWidth(widths[c] - 4)
                cell:Show()
            else cell:Hide() end
        end
        row.inView = i <= visible
        if not row.inView then row:Hide() end
    end
    Window.visible, Window.colX, Window.colW = visible, x, widths
end

local function fill(row, data)
    row.data = data
    local spec = Window.Spec()
    local icon = data.icon
    if spec == TABS.historyItem then icon = select(4, ns.Compat.ItemInfo(Window.historyItem)) end
    row.icon:SetTexture(icon or 134400)
    for c, column in ipairs(spec) do row.cells[c]:SetText(column[3](data) or "") end
    -- Price bar behind one column, scaled to the highest value shown.
    local barColumn = spec.barColumn
    local value = barColumn and spec[barColumn][2](data)
    if value and Window.barMax and Window.barMax > 0 then
        row.bar:ClearAllPoints()
        row.bar:SetPoint("LEFT", Window.colX[barColumn] - 2, 0)
        row.bar:SetWidth(math.max(1, (Window.colW[barColumn] - 6) * value / Window.barMax))
        row.bar:Show()
    else
        row.bar:Hide()
    end
    row:Show()
end

function Window.Refresh()
    local frame = Window.frame
    if not frame or not frame:IsShown() then return end
    layout()
    local data = Window.Data()
    Window.offset = math.max(0, math.min(Window.offset, #data - Window.visible))
    local spec = Window.Spec()
    Window.barMax = nil
    if spec.barColumn then
        for _, entry in ipairs(data) do
            local v = spec[spec.barColumn][2](entry)
            if v and v > (Window.barMax or 0) then Window.barMax = v end
        end
    end
    frame.back:SetShown(spec == TABS.historyItem)
    local state = sortState()
    for i, header in ipairs(frame.headers) do
        local column = Window.Spec()[i]
        if column then
            local arrow = state.column == i and (state.descending and " |cffffd100v|r" or " |cffffd100^|r") or ""
            header.text:SetText(column[1] .. arrow)
        end
    end
    for i, row in ipairs(frame.rows) do
        local entry = row.inView and data[i + Window.offset]
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
        if MARKET_STATUS[ns.Market.state] then status = MARKET_STATUS[ns.Market.state] end
        local open = ns.Compat.AuctionHouseOpen()
        frame.scan:SetEnabled(open and not s.running)
        frame.scan:Show()
        Window.UpdateMarketButton()
        frame.market:Show()
        frame.filter:Hide()
    else
        frame.scan:Hide()
        frame.market:Hide()
        frame.filter:SetShown(Window.tab == "recipes")
        frame.filter:SetText(ns.RecipeShop.FilterLabel())
        if Window.tab == "recipes" then
            status = #data .. " money-making recipes you don't know. Skill: |cff4ade80can learn|r "
                .. "|cfff87171need skill|r |cfffbbf24open profession once|r |cff9ca3afnot yours|r"
        elseif Window.tab == "vendor" then
            local sources = LibQuestieDB and "your vendor visits + Questie" or "vendors you have opened (install Questie for more)"
            status = #data .. " vendor items selling for 20%+ more on the AH. From " .. sources
                .. ". |cff9ca3af*|r = list price, open the vendor for exact."
        elseif Window.tab == "history" and Window.historyItem then
            local name = ns.Compat.ItemInfo(Window.historyItem) or ("item " .. Window.historyItem)
            local perDay, through = ns.Market.Rate(Window.historyItem)
            status = name .. ": prices from Auctionator, sales from Flipper's full scans."
            if perDay then
                status = status .. string.format(" ~%s sold/day", ns.Market.FormatRate(perDay):gsub("/d", ""))
                if through then status = status .. string.format(", %d%% sell", math.floor(through * 100 + 0.5)) end
            end
        elseif Window.tab == "history" then
            status = #data == 0
                and "No sales history yet: press Full scan on the AH flips tab on each AH visit. Right-click any row to see one item."
                or string.format("%d items, %.0f hours of AH watched (last %d days). Right-click any row in any tab for its history.",
                    #data, ns.History.HoursWatched(), ns.Market.WINDOW_DAYS)
        elseif Window.tab == "crafts" then
            status = #data == 0 and "Open each profession window once to teach Flipper your recipes."
                or (#data .. " recipes, AH prices from " .. (ns.Prices.Source() or "nothing"))
        else
            status = "Prices from " .. (ns.Prices.Source() or "nothing (install Auctionator)") .. ", after the 5% AH cut."
        end
    end
    if #data > Window.visible then
        status = string.format("%s  [%d-%d of %d]", status, Window.offset + 1,
            math.min(#data, Window.offset + Window.visible), #data)
    end
    frame.status:SetText(status)
end

-- Progress bar for whichever scan is running. A known total fills the bar; an unknown one
-- sweeps back and forth. Always shows the elapsed time. Called every tick (0.1 s).
function Window.UpdateProgress()
    local frame = Window.frame
    if not frame or not frame:IsShown() then return end
    local fraction, label, elapsed = ns.Market.Progress()
    if not label then fraction, label, elapsed = ns.Scanner.Progress() end
    local bar = frame.progress
    if not label then bar:Hide(); return end
    if not fraction then
        local t = (elapsed % 2) / 2                     -- 0..1 every 2 seconds
        fraction = t < 0.5 and t * 2 or (1 - t) * 2     -- there and back
        bar:SetStatusBarColor(0.38, 0.65, 0.98)
    else
        bar:SetStatusBarColor(0.29, 0.87, 0.5)
    end
    bar:SetValue(math.max(0.02, math.min(1, fraction)))
    bar.text:SetText(string.format("%s  (%d:%02d)", label, math.floor(elapsed / 60), math.floor(elapsed % 60)))
    bar:Show()
end

-- Full scan button: shows the cooldown countdown. Called on refresh and once a second.
function Window.UpdateMarketButton()
    local frame = Window.frame
    if not frame or not frame:IsShown() or Window.tab ~= "flips" then return end
    local wait = ns.Market.CooldownLeft()
    frame.market:SetEnabled(ns.Compat.AuctionHouseOpen() and wait == 0 and not MARKET_STATUS[ns.Market.state])
    frame.market:SetText(wait > 0 and string.format("Full %d:%02d", math.floor(wait / 60), wait % 60) or "Full scan")
end

local function clickHeader(index)
    local state = sortState()
    if state.column == index then
        state.descending = not state.descending
    else
        -- Names read best A-Z; money and counts best largest first.
        state.column, state.descending = index, index ~= 1
    end
    Window.offset = 0
    Window.Refresh()
end

function Window.CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, TOP_ROWS_Y - (index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", 8, 0)
    -- History tab: bar behind the price column, scaled to the highest price shown.
    row.bar = row:CreateTexture(nil, "BACKGROUND")
    row.bar:SetHeight(ROW_HEIGHT - 8)
    row.bar:SetColorTexture(0.29, 0.87, 0.5, 0.25)
    row.bar:Hide()
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.cells = {}
    for c = 1, MAX_COLUMNS do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        row.cells[c] = cell
    end
    row:SetScript("OnEnter", function(self)
        if not self.data or not self.data.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.data.itemID)
        local sellers = self.data.sellers
        if sellers and #sellers > 0 then
            GameTooltip:AddLine("Sold by:", 1, 0.82, 0)
            for _, seller in ipairs(sellers) do
                GameTooltip:AddLine("  " .. ns.Vendors.Describe(seller), 1, 1, 1)
            end
        end
        if Window.tab == "vendor" then
            GameTooltip:AddLine("Click: map pin to the vendor. Shift-click: check the AH in Auctionator.", 0.3, 0.9, 0.5, true)
        elseif Window.tab == "recipes" and sellers then
            GameTooltip:AddLine("Click: open in Auctionator. Shift-click: map pin to the vendor.", 0.3, 0.9, 0.5, true)
        elseif Window.tab == "flips" or Window.tab == "recipes" then
            GameTooltip:AddLine("Click: open in Auctionator to buy", 0.3, 0.9, 0.5)
        end
        if Window.tab == "history" then
            GameTooltip:AddLine("Click: day-by-day history", 0.3, 0.9, 0.5)
        else
            GameTooltip:AddLine("Right-click: price and sales history", 0.3, 0.9, 0.5)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local data = self.data
        if not data then return end
        if data.itemID and (button == "RightButton" or Window.tab == "history") then
            Window.ShowHistory(data.itemID)
            return
        end
        local pin = (Window.tab == "vendor") ~= IsShiftKeyDown()
        if Window.tab == "vendor" or Window.tab == "recipes" then
            if pin and data.sellers and data.sellers[1] then ns.Vendors.Waypoint(data.sellers[1]); return end
        end
        if Window.tab == "flips" or Window.tab == "recipes" or Window.tab == "vendor" then
            ns.Scanner.OpenInAuctionator(data)
        end
    end)
    return row
end

local function saveGeometry(frame)
    local saved = FlipperDB.window
    saved.width, saved.height = math.floor(frame:GetWidth()), math.floor(frame:GetHeight())
    -- While docked the position is relative to the AH frame; only the size is worth keeping.
    if Window.docked then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function restorePosition(frame)
    local saved = FlipperDB.window
    frame:ClearAllPoints()
    frame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 0, saved.y or 0)
end

------------------------------------------------------------------------
-- Docking beside the auction house. Flipper's window is anchored to the AH frame's right
-- edge; nothing on Blizzard's AH frame is changed, so buying stays untainted.
------------------------------------------------------------------------
function Window.OnAuctionHouseShow()
    local ah = AuctionHouseFrame
    if not ah then return end
    if not Window.ahButton then
        -- A child button that only sits on top of the AH frame: shows/hides Flipper.
        local button = CreateFrame("Button", "FlipperAHButton", ah, "UIPanelButtonTemplate")
        button:SetSize(76, 22)
        button:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", -28, 1)
        button:SetText("Flipper")
        button:SetScript("OnClick", function()
            local frame = Window.Create()
            if frame:IsShown() then frame:Hide() else Window.Dock(); frame:Show() end
        end)
        Window.ahButton = button
    end
    if FlipperDB.dock ~= false then
        Window.autoShown = not (Window.frame and Window.frame:IsShown())
        Window.Dock()
        Window.Toggle("flips")
    end
end

function Window.Dock()
    local frame, ah = Window.Create(), AuctionHouseFrame
    if not ah or FlipperDB.dock == false then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
    Window.docked = true
end

function Window.OnAuctionHouseClosed()
    if not Window.docked or not Window.frame then return end
    Window.docked = false
    if Window.autoShown then Window.frame:Hide() end
    restorePosition(Window.frame)
end

function Window.Create()
    if Window.frame then return Window.frame end
    local saved = FlipperDB.window
    local frame = CreateFrame("Frame", "FlipperFrame", UIParent, "BasicFrameTemplateWithInset")
    Window.frame = frame
    frame:SetSize(saved.width or DEFAULT_W, saved.height or DEFAULT_H)
    frame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 0, saved.y or 0)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); saveGeometry(self) end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "FlipperFrame")
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("Flipper")

    frame.tabs = {}
    for i, key in ipairs(TAB_ORDER) do
        local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        tab:SetSize(72, 22)
        tab:SetPoint("TOPLEFT", PAD + (i - 1) * 75, -28)
        tab:SetText(TAB_LABEL[key])
        tab:SetScript("OnClick", function()
            Window.tab, Window.offset = key, 0
            if key == "history" then Window.historyItem = nil end
            Window.Refresh()
        end)
        frame.tabs[key] = tab
    end
    frame.scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.scan:SetSize(90, 22)
    frame.scan:SetPoint("TOPRIGHT", -PAD, -28)
    frame.scan:SetText("Scan")
    frame.scan:SetScript("OnClick", function() ns.Scanner.Start() end)

    -- Full scan: snapshot of every auction, compared with the last one to estimate sales.
    frame.market = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.market:SetSize(90, 22)
    frame.market:SetPoint("RIGHT", frame.scan, "LEFT", -4, 0)
    frame.market:SetText("Full scan")
    frame.market:SetScript("OnClick", function() ns.Market.Start() end)
    frame.market:SetMotionScriptsWhileDisabled(true)
    frame.market:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Full scan: estimate sales")
        GameTooltip:AddLine("Records every auction. Each later full scan compares against it to estimate how many sold, "
            .. "expired or were relisted. Run one every AH visit; the Sold/day columns fill in over a few days. "
            .. "Limited to one every 15 minutes; may freeze the game for a moment.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.market:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.market:Hide()

    -- Recipes tab: which professions to show. Click cycles through the choices.
    frame.filter = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.filter:SetSize(130, 22)
    frame.filter:SetPoint("TOPRIGHT", -PAD, -28)
    frame.filter:SetScript("OnClick", function()
        ns.RecipeShop.NextFilter()
        Window.offset = 0
        Window.Refresh()
    end)
    frame.filter:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Professions shown")
        GameTooltip:AddLine("Click to cycle: yours, each of yours, every profession.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.filter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.filter:Hide()

    -- History, one item: back to the summary.
    frame.back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.back:SetSize(100, 22)
    frame.back:SetPoint("TOPRIGHT", -PAD, -28)
    frame.back:SetText("< All items")
    frame.back:SetScript("OnClick", function() Window.historyItem, Window.offset = nil, 0; Window.Refresh() end)
    frame.back:Hide()

    frame.headers = {}
    for i = 1, MAX_COLUMNS do
        local header = CreateFrame("Button", nil, frame)
        header:SetHeight(16)
        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.text:SetPoint("LEFT")
        header.text:SetJustifyH("LEFT")
        header:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        header:SetScript("OnClick", function() clickHeader(i) end)
        frame.headers[i] = header
    end
    frame.rows = {}

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        Window.offset = math.max(0, Window.offset - delta * 3)
        Window.Refresh()
    end)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.status:SetPoint("BOTTOMLEFT", 14, 12)
    frame.status:SetPoint("BOTTOMRIGHT", -24, 12)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    frame.progress = CreateFrame("StatusBar", nil, frame)
    frame.progress:SetPoint("BOTTOMLEFT", 14, 28)
    frame.progress:SetPoint("BOTTOMRIGHT", -24, 28)
    frame.progress:SetHeight(14)
    frame.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progress:SetMinMaxValues(0, 1)
    frame.progress.bg = frame.progress:CreateTexture(nil, "BACKGROUND")
    frame.progress.bg:SetAllPoints()
    frame.progress.bg:SetColorTexture(0, 0, 0, 0.5)
    frame.progress.text = frame.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.progress.text:SetPoint("CENTER")
    frame.progress:Hide()

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); saveGeometry(frame); Window.Refresh() end)

    -- Live relayout while dragging, at most ten times a second.
    local pending
    frame:SetScript("OnSizeChanged", function()
        if pending then return end
        pending = true
        C_Timer.After(0.1, function() pending = false; Window.Refresh() end)
    end)
    frame:SetScript("OnShow", Window.Refresh)
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

-- /flip reset: back to the default size and position.
function Window.ResetGeometry()
    FlipperDB.window.width, FlipperDB.window.height, FlipperDB.window.point = nil, nil, nil
    if Window.frame then
        Window.frame:ClearAllPoints()
        Window.frame:SetSize(DEFAULT_W, DEFAULT_H)
        Window.frame:SetPoint("CENTER")
        Window.Refresh()
    end
end
