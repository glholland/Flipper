-- Main window: Flips (AH below vendor), Bags (best use), Crafts (recipe margins), Recipes (to buy).
-- Resizable (drag the bottom-right corner); click a column header to sort, again to reverse.
local _, ns = ...
local Window = {tab = "flips", offset = 0}
ns.Window = Window
local Money = ns.Money

local ROW_HEIGHT, HEADER_Y, TOP_ROWS_Y = 22, -84, -102
local STRIP_Y, RULE_Y = -53, -78           -- scan controls and tab controls sit on one strip
local VALUE_WIDTH, ICON_SPACE, PAD = 92, 34, 12
local MIN_W, MIN_H, MAX_W, MAX_H = 680, 300, 1400, 1000
local DEFAULT_W, DEFAULT_H = 760, 440
local TAB_ORDER = {"deals", "flips", "vendor", "bags", "crafts", "recipes", "history"}
local TAB_LABEL = {deals = "Deals", flips = "Sell to vendor", vendor = "Buy from vendor", bags = "Bags", crafts = "Crafts", recipes = "Recipes",
    history = "History"}

local ACTION_TEXT = {ah = "|cff60a5faAuction|r", vendor = "Vendor", craft = "|cff4ade80Craft|r",
    disenchant = "|cffc084fcDisenchant|r", none = "|cff9ca3af-|r"}
local RECIPE_STATUS = {
    learnable = "|cff4ade80%d|r", skill = "|cfff87171%d|r", other = "|cff9ca3af%d|r", unverified = "|cfffbbf24%d?|r",
}
local STATUS = {
    idle = "Open the AH and press Quick scan.", browse = "Quick scan: browsing the auction house...",
    evaluating = "Checking vendor prices...", closed = "Open the auction house to scan.",
    unsupported = "This client has no modern AH API.", interrupted = "Quick scan stopped: another search started.",
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
        {"Qty", function(r) return r.quantity end, function(r) return tostring(r.quantity) end, 56},
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
            if not r.margin.value then return GREY_NO_PRICE end
            return Money.Format(r.margin.value) .. (r.margin.sellTo == "vendor" and " |cff9ca3af(vendor)|r" or "")
        end, 130},
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
local function percent(change)
    if not change then return count(nil) end
    local p = math.floor(change * 100 + 0.5)
    if p > 0 then return "|cfff87171+" .. p .. "%|r" end   -- pricier than usual: red for buyers
    if p < 0 then return "|cff4ade80" .. p .. "%|r" end     -- cheaper than usual: green
    return "0%"
end

-- Deals: listed well below the usual price. Profit assumes reselling at the average.
TABS.deals = {
    default = {4, true},
    {"Item", function(r) return r.name end, function(r) return qualityName(r) end},
    {"Now", function(r) return r.latest end, function(r) return Money.Format(r.latest) end},
    {"Usual", function(r) return r.average end, function(r) return Money.Format(r.average) end},
    {"Profit/ea", function(r) return r.profit end, function(r) return green(Money.Format(r.profit)) end},
    {"vs usual", function(r) return r.change end, function(r) return percent(r.change) end, 64},
    {"Days seen", function(r) return r.daysTracked end, function(r) return count(r.daysTracked) end, 70},
    {"Sold/day", function(r) return r.perDay end, function(r) return ns.Market.FormatRate(r.perDay) end, 70},
}
TABS.history = {
    sortKey = "history:v2",
    default = {6, false},
    {"Item", function(r) return r.name end, function(r) return qualityName(r) end},
    {"Now", function(r) return r.latest end, function(r) return r.latest and Money.Format(r.latest) or count(nil) end, 100},
    {"21-day avg", function(r) return r.average end, function(r) return r.average and Money.Format(r.average) or count(nil) end, 100},
    {"vs avg", function(r) return r.change end, function(r) return percent(r.change) end, 64},
    {"Listed", function(r) return r.listed end, function(r) return count(r.listed) end, 60},
    {"Last seen", function(r) return r.lastSeen end, function(r)
        if not r.lastSeen then return count(nil) end
        return r.lastSeen == 0 and "today" or (r.lastSeen .. "d ago")
    end, 76},
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
    {"Cancelled", function(r) return r.cancelled end, function(r) return count(r.cancelled) end, 64},
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
-- Text columns read left to right; everything else is a number and right-aligns.
local LEFT_ALIGNED = {["Best use"] = true, ["Where to buy"] = true}
-- Shown in the middle of an empty list.
local EMPTY = {
    deals = "No deals right now.\nDeals are items listed at 70% or less of their usual price.\nRun a Full scan (or an Auctionator scan) for fresh prices.",
    flips = "Nothing to sell to a vendor yet.\nWith the auction house open, press Quick scan or Full scan to find listings\ncheaper than what a vendor pays for them.",
    vendor = "No vendor flips found.\nOpen vendors as you travel (Flipper remembers their stock),\nor install Questie to know every vendor.",
    bags = "Your bags are empty, or item info is still loading.",
    crafts = "No recipes known yet.\nOpen each profession window once so Flipper can learn your recipes.",
    recipes = "No money-making recipes right now.\nScan the AH with Auctionator for fresh prices, or try another profession filter.",
    history = "No items found.\nAuctionator has no prices from the last 14 days (scan the AH with it),\nor nothing matches your search.",
}
local MARKET_STATUS = {
    timeout = "Full scan: the AH didn't answer. Try again.", unsupported = "Full scans aren't available on this client.",
    closed = "Full scan stopped: the AH closed. The 15-minute limit still applies.",
}
local NOTICE_SECONDS = 10

local function craftRows()
    local rows = {}
    for _, recipe in ns.Recipes.All() do
        local name, _, quality, icon = ns.Compat.ItemInfo(recipe.output)
        rows[#rows + 1] = {name = recipe.name or name or "?", quality = quality, icon = icon,
            itemID = recipe.output, margin = ns.Logic.CraftMargin(recipe, ns.Prices.Buy, ns.AH_CUT, ns.Prices.Fair, ns.Prices.Vendor)}
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
    if Window.tab == "deals" then rows = ns.Deals.Rows()
    elseif Window.tab == "flips" then
        rows = {}
        for i, row in ipairs(ns.Scanner.rows) do rows[i] = row end  -- don't reorder the scanner's own list
    elseif Window.tab == "vendor" then
        rows = {}
        for i, row in ipairs(ns.Vendors.FlipRows()) do rows[i] = row end
    elseif Window.tab == "bags" then rows = ns.Bags.Rows()
    elseif Window.tab == "recipes" then rows = ns.RecipeShop.Rows()
    elseif Window.tab == "history" then
        rows = Window.historyItem and ns.History.ItemDays(Window.historyItem) or ns.History.Summary(Window.historySearch)
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
    local columnCount = #columns
    local widths, fixed = {}, 0
    for i = 2, columnCount do widths[i] = columns[i][4] or VALUE_WIDTH; fixed = fixed + widths[i] end
    -- The name column grows up to about half the width; any space beyond that is shared by the
    -- value columns, so numbers don't end up stranded at the far right of a wide window.
    local available = width - 2 * PAD - ICON_SPACE - fixed
    widths[1] = math.max(140, math.min(available, math.floor((width - 2 * PAD) * 0.48)))
    local spare = math.max(0, available - widths[1])
    for i = 2, columnCount do widths[i] = widths[i] + math.floor(spare / (columnCount - 1)) end
    local x = {ICON_SPACE}
    for i = 2, columnCount do x[i] = x[i - 1] + widths[i - 1] end
    local align = {}
    for i = 1, columnCount do align[i] = (i == 1 or LEFT_ALIGNED[columns[i][1]]) and "LEFT" or "RIGHT" end
    for i, header in ipairs(frame.headers) do
        header:ClearAllPoints()
        if i <= columnCount then
            header:SetPoint("TOPLEFT", PAD + x[i], HEADER_Y)
            header:SetWidth(widths[i] - 10)
            header.text:SetJustifyH(align[i])
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
            if c <= columnCount then
                cell:SetPoint("LEFT", x[c], 0)
                cell:SetWidth(widths[c] - 10)
                cell:SetJustifyH(align[c])
                cell:Show()
            else cell:Hide() end
        end
        row.stripe:SetShown(i % 2 == 0)
        row.inView = i <= visible
        if not row.inView then row:Hide() end
    end
    Window.visible, Window.colX, Window.colW = visible, x, widths
end

local function fill(row, data)
    row.data = data
    -- Big lists skip item loads while building; only rows on screen ask for them.
    if data.needsInfo then
        local name, _, quality, icon = ns.Compat.ItemInfo(data.itemID)
        if name then data.name, data.quality, data.icon, data.needsInfo = name, quality, icon, nil end
    end
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
    if not frame or not frame:IsVisible() then return end
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
    frame.search:SetShown(spec == TABS.history)
    local emptyText = spec == TABS.historyItem and "No price or sales data for this item yet." or EMPTY[Window.tab]
    frame.empty:SetText(#data == 0 and emptyText or "")
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
    for key, button in pairs(frame.tabs) do button:SetSelected(key == Window.tab) end
    local status
    Window.UpdateScanButtons()
    frame.filter:SetShown(Window.tab == "recipes")
    if Window.tab == "flips" then
        local s = ns.Scanner
        status = STATUS[s.state] or ""
        if s.state == "done" then
            if s.source == "full" then
                status = string.format("%d items below vendor price, from the last full scan (Qty = how many are below it).", #s.rows)
            else
                status = string.format("%d items below vendor price, from the last quick scan (Qty = all listed).", #s.rows)
            end
            if s.deferred > 0 then status = status .. string.format(" %d items had no data yet.", s.deferred) end
        end
        if MARKET_STATUS[ns.Market.state] then status = MARKET_STATUS[ns.Market.state] end
    else
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
            local hours = ns.History.HoursWatched()
            status = string.format("%d items priced by Auctionator in the last 14 days. Click one for its daily history.", #data)
                .. (hours > 0 and string.format(" Sales watched %.0fh.", hours)
                    or " Sold/day starts after two Full scans 15 min to 12 h apart.")
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
    -- A scan that just finished says what it updated, on every tab, for a few seconds.
    if Window.notice and GetTime() < Window.noticeUntil then status = "|cffffffff" .. Window.notice .. "|r" end
    frame.status:SetText(status)
    Window.UpdateAge()
end

-- "Prices 3m old · Sales 6h old" at the bottom right of every tab.
local function age(seconds)
    if seconds < 3600 then return math.max(0, math.floor(seconds / 60)) .. "m" end
    if seconds < 172800 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end
function Window.UpdateAge()
    local frame = Window.frame
    if not frame then return end
    local now = time()
    local full, summary = ns.Market.AuctionatorTimes()
    local priced = math.max(full or 0, summary or 0, ns.Market.LastFullScan() or 0, ns.Scanner.doneAt or 0)
    local sales = ns.Market.LastFullScan()
    local parts = {}
    parts[1] = priced > 0 and ("Prices " .. age(now - priced) .. " old") or "No scans yet"
    if not sales then
        parts[2] = "|cfffbbf24no sales data: run a Full scan|r"
    elseif now - sales > 6 * 3600 then
        parts[2] = "|cfffb923cSales " .. age(now - sales) .. " old: run a Full scan|r"
    else
        parts[2] = "Sales " .. age(now - sales) .. " old"
    end
    frame.age:SetText("|cff9ca3af" .. table.concat(parts, "  \194\183  ") .. "|r")
end

-- Called when a scan finishes: shows its summary on every tab.
function Window.Notice(text)
    if not text then return end
    Window.notice, Window.noticeUntil = text, GetTime() + NOTICE_SECONDS
    C_Timer.After(NOTICE_SECONDS + 0.1, function() if Window.IsVisible() then Window.Refresh() end end)
end

-- Progress bar for whichever scan is running. A known total fills the bar; an unknown one
-- sweeps back and forth. Always shows the elapsed time. Called every tick (0.1 s).
function Window.UpdateProgress()
    local frame = Window.frame
    if not frame or not frame:IsVisible() then return end
    local fraction, label, elapsed = ns.Market.Progress()
    if not label then fraction, label, elapsed = ns.Scanner.Progress() end
    if not label and ns.Market.AuctionatorScanning() then
        Window.auctionatorSince = Window.auctionatorSince or GetTime()
        fraction, label, elapsed = nil, "Auctionator is scanning; Flipper will use its results", GetTime() - Window.auctionatorSince
    elseif not ns.Market.AuctionatorScanning() then
        Window.auctionatorSince = nil
    end
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

-- Whether any scan is running: Flipper's or Auctionator's.
function Window.ScanBusy()
    return ns.Scanner.Busy() or ns.Market.Busy() or ns.Market.AuctionatorScanning()
end

-- Scan buttons on every tab. Called on refresh and once a second (the cooldown countdown).
function Window.UpdateScanButtons()
    local frame = Window.frame
    if not frame or not frame:IsVisible() then return end
    local open, busy = ns.Compat.AuctionHouseOpen(), Window.ScanBusy()
    local wait = ns.Market.CooldownLeft()
    frame.scan:SetEnabled(open and not busy)
    frame.market:SetEnabled(open and not busy and wait == 0)
    frame.market:SetText(wait > 0 and string.format("Full scan %d:%02d", math.floor(wait / 60), wait % 60) or "Full scan")
    frame.auto:SetChecked(FlipperDB.autoQuickScan and true or false)
    Window.UpdateAge()
end
Window.UpdateMarketButton = Window.UpdateScanButtons

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
    row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.035)
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
        elseif Window.tab == "flips" or Window.tab == "recipes" or Window.tab == "deals" then
            GameTooltip:AddLine("Click: open in Auctionator to buy", 0.3, 0.9, 0.5)
        elseif Window.tab == "bags" and self.data.bagSlot then
            GameTooltip:AddLine("Click: sell it in Auctionator's Selling tab", 0.3, 0.9, 0.5)
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
        if Window.tab == "bags" then ns.Bags.SellInAuctionator(data); return end
        local pin = (Window.tab == "vendor") ~= IsShiftKeyDown()
        if Window.tab == "vendor" or Window.tab == "recipes" then
            if pin and data.sellers and data.sellers[1] then ns.Vendors.Waypoint(data.sellers[1]); return end
        end
        if (Window.tab == "flips" or Window.tab == "recipes" or Window.tab == "vendor" or Window.tab == "deals")
            and not data.needsInfo then
            ns.Scanner.OpenInAuctionator(data)
        end
    end)
    return row
end

local function saveGeometry(floating)
    local saved = FlipperDB.window
    saved.width, saved.height = math.floor(floating:GetWidth()), math.floor(floating:GetHeight())
    local point, _, relativePoint, x, y = floating:GetPoint(1)
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

-- The content (tabs, list, buttons) lives in Window.frame and is shown in one host at a
-- time: the floating window, or the Flipper tab inside the auction house.
function Window.AttachTo(host)
    local frame = Window.Create()
    if frame:GetParent() == host then return end
    frame:SetParent(host)
    frame:ClearAllPoints()
    if host == Window.floating then
        frame:SetAllPoints(host)
    else
        frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 8)    -- Flipper's tab strip replaces the AH's search row
        frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    end
    frame:Show()
    Window.Refresh()
end

function Window.IsVisible()
    return Window.frame and Window.frame:IsVisible() or false
end

------------------------------------------------------------------------
-- Flipper tab in the auction house, through LibAHTab (shipped with Auctionator), the same
-- library Auctionator's and Disenchantry's tabs use. Flipper's view fills the AH's content
-- area while its tab is selected; Blizzard's own tab list isn't modified.
------------------------------------------------------------------------
function Window.OnAuctionHouseShow()
    local ah = AuctionHouseFrame
    if not ah or Window.ahPanel then return end
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not lib then return end   -- without Auctionator: use /flip for the floating window
    local panel = CreateFrame("Frame", "FlipperAHPanel", ah)
    panel:SetPoint("TOPLEFT", ah, "TOPLEFT", 5, -34)          -- same area Disenchantry's tab uses
    panel:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -5, 5)
    panel:SetFrameLevel(ah:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    panel:SetScript("OnShow", function(self)
        if Window.floating then Window.floating:Hide() end
        Window.AttachTo(self)
    end)
    local ok = pcall(lib.CreateTab, lib, "Flipper", panel, "Flipper", "Flipper")
    if ok then Window.ahPanel = panel end
end

function Window.OnAuctionHouseClosed() end

function Window.Create()
    if Window.frame then return Window.frame end
    local saved = FlipperDB.window
    -- Floating window: title bar, dragging, resize grip.
    local floating = CreateFrame("Frame", "FlipperFrame", UIParent, "BasicFrameTemplateWithInset")
    Window.floating = floating
    floating:SetSize(saved.width or DEFAULT_W, saved.height or DEFAULT_H)
    floating:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 0, saved.y or 0)
    floating:SetMovable(true)
    floating:SetResizable(true)
    if floating.SetResizeBounds then floating:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    floating:EnableMouse(true)
    floating:RegisterForDrag("LeftButton")
    floating:SetScript("OnDragStart", floating.StartMoving)
    floating:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); saveGeometry(self) end)
    floating:SetClampedToScreen(true)
    floating:SetFrameStrata("HIGH")
    floating:Hide()
    tinsert(UISpecialFrames, "FlipperFrame")
    floating.title = floating:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    floating.title:SetPoint("TOP", 0, -5)
    floating.title:SetText("Flipper")
    floating:SetScript("OnShow", function(self) Window.AttachTo(self) end)

    -- Content frame, moved between hosts.
    local frame = CreateFrame("Frame", nil, floating)
    Window.frame = frame
    frame:SetAllPoints(floating)

    -- Flat text tabs: grey, white on hover, gold with an underline when selected.
    frame.tabs = {}
    local previous
    for _, key in ipairs(TAB_ORDER) do
        local tab = CreateFrame("Button", nil, frame)
        tab:SetHeight(22)
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.label:SetPoint("CENTER", 0, 1)
        tab.label:SetText(TAB_LABEL[key])
        tab:SetWidth(tab.label:GetStringWidth() + 20)
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 2, 0) else tab:SetPoint("TOPLEFT", PAD, -27) end
        tab.underline = tab:CreateTexture(nil, "ARTWORK")
        tab.underline:SetPoint("BOTTOMLEFT", 6, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -6, 0)
        tab.underline:SetHeight(2)
        tab.underline:SetColorTexture(1, 0.82, 0, 1)
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.06)
        tab.SetSelected = function(self, selected)
            self.underline:SetShown(selected)
            if selected then self.label:SetTextColor(1, 0.82, 0) else self.label:SetTextColor(0.7, 0.7, 0.7) end
        end
        tab:SetScript("OnEnter", function(self) if not self.underline:IsShown() then self.label:SetTextColor(1, 1, 1) end end)
        tab:SetScript("OnLeave", function(self) self:SetSelected(self.underline:IsShown()) end)
        tab:SetScript("OnClick", function()
            Window.tab, Window.offset = key, 0
            if key == "history" then Window.historyItem = nil end
            Window.Refresh()
        end)
        frame.tabs[key] = tab
        previous = tab
    end
    -- Line under the tab strip, and a darker inset behind the list.
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", PAD, RULE_Y)
    rule:SetPoint("TOPRIGHT", -PAD, RULE_Y)
    rule:SetHeight(1)
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    local inset = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inset:SetPoint("TOPLEFT", PAD, TOP_ROWS_Y + 2)
    inset:SetPoint("BOTTOMRIGHT", -PAD, 46)
    inset:SetColorTexture(0, 0, 0, 0.35)
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER", inset, "CENTER")
    frame.empty:SetWidth(420)
    frame.empty:SetSpacing(4)
    -- Scan controls, on every tab: Quick scan, Full scan, auto quick scan.
    local function tooltip(button, title, text)
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(title)
            GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
            if not ns.Compat.AuctionHouseOpen() then GameTooltip:AddLine("Open the auction house first.", 1, 0.5, 0.5) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    frame.scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.scan:SetSize(96, 22)
    frame.scan:SetPoint("TOPLEFT", PAD, STRIP_Y)
    frame.scan:SetText("Quick scan")
    frame.scan:SetScript("OnClick", function() ns.Scanner.Start() end)
    tooltip(frame.scan, "Quick scan", "Cheapest price of every item. A few seconds, no limit. "
        .. "Updates Sell to vendor. Doesn't change sales estimates.")

    frame.market = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.market:SetSize(116, 22)
    frame.market:SetPoint("LEFT", frame.scan, "RIGHT", 4, 0)
    frame.market:SetText("Full scan")
    frame.market:SetScript("OnClick", function() ns.Market.Start() end)
    tooltip(frame.market, "Full scan", "Every listing. May freeze the game for a few seconds. "
        .. "Once per 15 minutes, shared with Auctionator (it updates Auctionator's prices too). "
        .. "Updates Sold/day, History and Sell to vendor. Two full scans 15 minutes to 12 hours apart estimate sales.")

    frame.auto = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.auto:SetSize(24, 24)
    frame.auto:SetPoint("LEFT", frame.market, "RIGHT", 6, 0)
    frame.auto.label = frame.auto:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.auto.label:SetPoint("LEFT", frame.auto, "RIGHT", 0, 1)
    frame.auto.label:SetText("Auto quick scan")
    frame.auto:SetHitRectInsets(0, -frame.auto.label:GetStringWidth() - 4, 0, 0)
    frame.auto:SetScript("OnClick", function(self) ns.Settings.Set("autoQuickScan", self:GetChecked()) end)
    tooltip(frame.auto, "Auto quick scan when the AH opens", "Runs a Quick scan a few seconds after you open the "
        .. "auction house. Skipped when Auctionator is set to scan on open (Flipper uses its scan), when prices are "
        .. "under 5 minutes old, or when you've already started a search. Never runs a Full scan.")

    -- Recipes tab: which professions to show. Click cycles through the choices.
    frame.filter = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.filter:SetSize(130, 22)
    frame.filter:SetPoint("TOPRIGHT", -PAD, STRIP_Y)
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
    frame.back:SetPoint("TOPRIGHT", -PAD, STRIP_Y)
    frame.back:SetText("< All items")
    frame.back:SetScript("OnClick", function() Window.historyItem, Window.offset = nil, 0; Window.Refresh() end)
    frame.back:Hide()

    -- History summary: filter by item name.
    -- Plain edit box (no template, so nothing depends on which Blizzard templates exist).
    frame.search = CreateFrame("EditBox", nil, frame)
    frame.search:SetSize(180, 20)
    frame.search:SetPoint("TOPRIGHT", -PAD - 2, STRIP_Y - 1)
    frame.search:SetAutoFocus(false)
    frame.search:SetFontObject("ChatFontNormal")
    frame.search:SetTextInsets(6, 6, 0, 0)
    local searchBg = frame.search:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetColorTexture(0, 0, 0, 0.6)
    local searchBorder = frame.search:CreateTexture(nil, "BORDER")
    searchBorder:SetPoint("BOTTOMLEFT")
    searchBorder:SetPoint("BOTTOMRIGHT")
    searchBorder:SetHeight(1)
    searchBorder:SetColorTexture(1, 0.82, 0, 0.5)
    frame.search.hint = frame.search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.search.hint:SetPoint("LEFT", 6, 0)
    frame.search.hint:SetText("Search items")
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    frame.search:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    -- Search once typing pauses (0.5 s after the last key), or right away on Enter.
    local function applySearch(text)
        if text == (Window.historySearch or "") then return end
        Window.historySearch, Window.offset = text, 0
        Window.Refresh()
    end
    local searchToken = 0
    frame.search:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        searchToken = searchToken + 1
        local token, text = searchToken, self:GetText()
        C_Timer.After(0.5, function() if token == searchToken then applySearch(text) end end)
    end)
    frame.search:SetScript("OnEnterPressed", function(self)
        searchToken = searchToken + 1
        applySearch(self:GetText())
        self:ClearFocus()
    end)
    frame.search:Hide()

    frame.headers = {}
    for i = 1, MAX_COLUMNS do
        local header = CreateFrame("Button", nil, frame)
        header:SetHeight(16)
        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.text:SetAllPoints()
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
    frame.age = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.age:SetPoint("BOTTOMRIGHT", -24, 12)
    frame.age:SetJustifyH("RIGHT")
    frame.status:SetPoint("BOTTOMLEFT", 14, 12)
    frame.status:SetPoint("BOTTOMRIGHT", frame.age, "BOTTOMLEFT", -12, 0)
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

    -- Resize grip belongs to the floating window (the AH decides its own size).
    local grip = CreateFrame("Button", nil, floating)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() floating:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() floating:StopMovingOrSizing(); saveGeometry(floating); Window.Refresh() end)

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

-- With a tab name: show that tab (inside the AH if Flipper's AH tab is open, else floating).
-- Without: toggle the floating window.
function Window.Toggle(tab)
    Window.Create()
    local inAH = Window.ahPanel and Window.ahPanel:IsVisible()
    if tab then
        Window.tab, Window.offset = tab, 0
        if not inAH then Window.floating:Show() end
        Window.Refresh()
    elseif Window.floating:IsShown() then Window.floating:Hide()
    else Window.floating:Show() end
end

-- /flip reset: back to the default size and position.
function Window.ResetGeometry()
    FlipperDB.window.width, FlipperDB.window.height, FlipperDB.window.point = nil, nil, nil
    if Window.floating then
        Window.floating:ClearAllPoints()
        Window.floating:SetSize(DEFAULT_W, DEFAULT_H)
        Window.floating:SetPoint("CENTER")
        Window.Refresh()
    end
end
