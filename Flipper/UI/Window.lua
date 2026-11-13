-- Main window: Flips (AH below vendor), Bags (best use), Crafts (recipe margins), Recipes (to buy).
-- Resizable (drag the bottom-right corner); click a column header to sort, again to reverse.
local _, ns = ...
local Window = {tab = "flips", offset = 0}
ns.Window = Window
local Money = ns.Money

local ROW_HEIGHT, HEADER_Y, TOP_ROWS_Y = 22, -52, -66
local VALUE_WIDTH, ICON_SPACE, PAD = 92, 34, 12
local MIN_W, MIN_H, MAX_W, MAX_H = 600, 260, 1400, 1000
local DEFAULT_W, DEFAULT_H = 760, 440
local TAB_ORDER = {"flips", "vendor", "bags", "crafts", "recipes"}
local TAB_LABEL = {flips = "AH flips", vendor = "Vendor", bags = "Bags", crafts = "Crafts", recipes = "Recipes"}

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
        {"Listed", function(r) return r.quantity end, function(r) return tostring(r.quantity) end},
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
        {"Skill", function(r) return r.skill end, function(r) return string.format(RECIPE_STATUS[r.status], r.skill) end},
    },
}
local MAX_COLUMNS = 6

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
    local key = TABS[Window.tab].sortKey or Window.tab
    local state = saved[key]
    if not state then
        local default = TABS[Window.tab].default
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
    else rows = craftRows() end
    local state = sortState()
    local column = TABS[Window.tab][state.column]
    if column then ns.Logic.SortRows(rows, column[2], state.descending) end
    return rows
end

-- Positions headers and cells for the current width: value columns have a fixed width
-- from the right edge, the name column takes whatever is left.
local function layout()
    local frame = Window.frame
    local width = frame:GetWidth()
    local columns = TABS[Window.tab]
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
    local visible = math.max(1, math.floor((frame:GetHeight() + TOP_ROWS_Y - 34) / ROW_HEIGHT))
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
    Window.visible = visible
end

local function fill(row, data)
    row.data = data
    row.icon:SetTexture(data.icon or 134400)
    for c, column in ipairs(TABS[Window.tab]) do row.cells[c]:SetText(column[3](data) or "") end
    row:Show()
end

function Window.Refresh()
    local frame = Window.frame
    if not frame or not frame:IsShown() then return end
    layout()
    local data = Window.Data()
    Window.offset = math.max(0, math.min(Window.offset, #data - Window.visible))
    local state = sortState()
    for i, header in ipairs(frame.headers) do
        local column = TABS[Window.tab][i]
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
        frame.scan:SetEnabled(ns.Compat.AuctionHouseOpen() and not s.running)
        frame.scan:Show()
        frame.filter:Hide()
    else
        frame.scan:Hide()
        frame.filter:SetShown(Window.tab == "recipes")
        frame.filter:SetText(ns.RecipeShop.FilterLabel())
        if Window.tab == "recipes" then
            status = #data .. " money-making recipes you don't know. Skill: |cff4ade80can learn|r "
                .. "|cfff87171need skill|r |cfffbbf24open profession once|r |cff9ca3afnot yours|r"
        elseif Window.tab == "vendor" then
            local sources = LibQuestieDB and "your vendor visits + Questie" or "vendors you have opened (install Questie for more)"
            status = #data .. " vendor items selling for 20%+ more on the AH. From " .. sources
                .. ". |cff9ca3af*|r = list price, open the vendor for exact."
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
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local data = self.data
        if not data then return end
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
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
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
        tab:SetSize(78, 22)
        tab:SetPoint("TOPLEFT", PAD + (i - 1) * 82, -28)
        tab:SetText(TAB_LABEL[key])
        tab:SetScript("OnClick", function() Window.tab, Window.offset = key, 0; Window.Refresh() end)
        frame.tabs[key] = tab
    end
    frame.scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.scan:SetSize(90, 22)
    frame.scan:SetPoint("TOPRIGHT", -PAD, -28)
    frame.scan:SetText("Scan")
    frame.scan:SetScript("OnClick", function() ns.Scanner.Start() end)

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
