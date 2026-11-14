-- Quick scan: browses the whole auction house once (cheapest price per item) and lists items
-- whose cheapest listing is below what a vendor pays. After a full scan the same list is
-- built from every listing instead, with the exact quantity below vendor price.
-- Browse paging and interruption handling adapted from Disenchantry's Core/AuctionScan.lua
-- (MIT, see NOTICE). Flipper never buys: rows open Auctionator's search.
-- Auctionator's own quick ("summary") scan sends the same empty browse query; when it runs,
-- Flipper reads its results instead of starting a second one.
local _, ns = ...
local Scanner = {rows = {}, state = "idle", total = 0, deferred = 0}
ns.Scanner = Scanner

local LOAD_WAIT_SECONDS = 5     -- how long to wait for uncached item info before giving up on it
local REQUEST_TIMEOUT = 30
local CHECKS_PER_TICK = 800     -- vendor-price checks per 0.1 s tick

local function changed()
    if Scanner.OnChanged then Scanner.OnChanged() end
end

function Scanner.Supported()
    local api = C_AuctionHouse
    for _, name in ipairs({"SendBrowseQuery", "GetBrowseResults", "HasFullBrowseResults", "RequestMoreBrowseResults"}) do
        if not api or type(api[name]) ~= "function" then return false end
    end
    return true
end

-- For the progress bar: fraction done (nil while the total is unknown), label, seconds running.
function Scanner.Progress()
    if not Scanner.running then return nil end
    local elapsed = GetTime() - (Scanner.startedAt or GetTime())
    if Scanner.state == "evaluating" then
        local total = #Scanner.queue
        return total > 0 and Scanner.cursor / total or 0,
            string.format("Checking vendor prices: %d / %d", Scanner.cursor, total), elapsed
    end
    local who = Scanner.passive and "Auctionator's quick scan" or "Quick scan"
    return nil, string.format("%s: %d items so far", who, Scanner.total), elapsed
end

function Scanner.Stop(reason)
    Scanner.running, Scanner.pending, Scanner.waiting, Scanner.passive = false, nil, nil, nil
    Scanner.state = reason or "stopped"
    changed()
end

local function request(name, ...)
    Scanner.pending = {name = name, args = {...}}
    Scanner.deadline = GetTime() + REQUEST_TIMEOUT
end

------------------------------------------------------------------------
-- Turning prices into rows
------------------------------------------------------------------------
-- Queue entries: {itemID, itemKey?, minPrice, quantity?, prices?, own?}. `prices` (from a full
-- scan) gives the exact quantity below vendor price; otherwise `quantity` is what's listed.

local function rowFor(entry, minProfit)
    local name, _, quality, icon, sellPrice = ns.Compat.ItemInfo(entry.itemID)
    if not name then return nil, true end
    if entry.own then return nil end
    sellPrice = ns.IsNumber(sellPrice) and sellPrice or 0
    local profit = ns.Logic.EvaluateFlip(entry.minPrice, sellPrice, minProfit)
    if not profit then return nil end
    local quantity = entry.quantity or 1
    if entry.prices then
        quantity = 0
        for price, listing in pairs(entry.prices) do
            if sellPrice - price >= minProfit then quantity = quantity + listing.q end
        end
    end
    return {itemID = entry.itemID, itemKey = entry.itemKey, name = name, icon = icon, quality = quality,
        minPrice = entry.minPrice, vendor = sellPrice, profit = profit, quantity = quantity}
end

local function finish()
    table.sort(Scanner.rows, function(a, b) return a.profit * a.quantity > b.profit * b.quantity end)
    Scanner.running, Scanner.state, Scanner.passive = false, "done", nil
    Scanner.doneAt = time()
    local found = #Scanner.rows
    if Scanner.source == "full" then
        Scanner.summary = nil  -- the full scan's own message covers it
    else
        Scanner.summary = string.format("Quick scan done: %d items, %d below vendor price. Sales estimates unchanged.",
            Scanner.total, found)
    end
    if Scanner.summary and ns.Window and ns.Window.Notice then ns.Window.Notice(Scanner.summary) end
    changed()
end

-- Checks a slice of the queue each tick; items whose info hasn't loaded go round again until
-- LOAD_WAIT_SECONDS passes.
local function evaluate()
    local minProfit = FlipperDB and FlipperDB.minFlipProfit or ns.DEFAULTS.minFlipProfit
    local queue = Scanner.queue
    local last = math.min(#queue, Scanner.cursor + CHECKS_PER_TICK)
    for i = Scanner.cursor + 1, last do
        local row, missing = rowFor(queue[i], minProfit)
        if row then Scanner.rows[#Scanner.rows + 1] = row
        elseif missing then Scanner.retry[#Scanner.retry + 1] = queue[i] end
    end
    Scanner.cursor = last
    if Scanner.cursor < #queue then return end
    if #Scanner.retry > 0 and GetTime() < Scanner.loadDeadline then
        Scanner.queue, Scanner.retry, Scanner.cursor = Scanner.retry, {}, 0
        return
    end
    Scanner.deferred = #Scanner.retry
    finish()
end

local function startEvaluating(queue, source)
    Scanner.rows, Scanner.queue, Scanner.retry, Scanner.cursor = {}, queue, {}, 0
    Scanner.deferred, Scanner.source = 0, source
    Scanner.running, Scanner.state = true, "evaluating"
    Scanner.startedAt = Scanner.startedAt or GetTime()
    Scanner.loadDeadline = GetTime() + LOAD_WAIT_SECONDS
    changed()
end

-- Rebuilds the list from a full scan: snapshot[itemID][unitPrice] = {q, tl}.
-- (The full scan doesn't say which listings are yours, so your own auctions aren't excluded.)
function Scanner.FromSnapshot(snapshot)
    if Scanner.running and Scanner.state ~= "evaluating" then return end   -- a quick scan is mid-browse
    local queue, items = {}, 0
    for itemID, prices in pairs(snapshot) do
        items = items + 1
        local minPrice
        for price in pairs(prices) do if not minPrice or price < minPrice then minPrice = price end end
        if minPrice then queue[#queue + 1] = {itemID = itemID, minPrice = minPrice, prices = prices} end
    end
    Scanner.total, Scanner.startedAt = items, GetTime()
    startEvaluating(queue, "full")
end

------------------------------------------------------------------------
-- Browsing
------------------------------------------------------------------------

local function resetBrowse(passive)
    Scanner.rows, Scanner.results, Scanner.seen, Scanner.total, Scanner.deferred = {}, {}, {}, 0, 0
    Scanner.running, Scanner.state, Scanner.startedAt, Scanner.passive = true, "browse", GetTime(), passive or nil
    Scanner.source, Scanner.pending, Scanner.waiting = "quick", nil, nil
    Scanner.deadline = GetTime() + REQUEST_TIMEOUT
end

function Scanner.Busy() return Scanner.running and true or false end

-- Auto quick scan when the AH opens (`openedAt` = GetTime() then). Skipped when the option
-- is off, any scan is running, Auctionator is set to scan on open (Flipper reads its scan),
-- you've searched since opening, or prices are under FRESH_SECONDS old. Returns true if it started.
local FRESH_SECONDS = 5 * 60
function Scanner.MaybeAutoScan(openedAt)
    if not FlipperDB or not FlipperDB.autoQuickScan or not ns.Compat.AuctionHouseOpen() then return false end
    local market = ns.Market
    if Scanner.running or market.Busy() or market.AuctionatorScanning() or market.AuctionatorAutoscans() then return false end
    if (Scanner.lastForeignSearch or -1) >= openedAt then return false end
    local full, summary = market.AuctionatorTimes()
    local newest = math.max(full or 0, summary or 0, market.LastFullScan() or 0, Scanner.doneAt or 0)
    if time() - newest < FRESH_SECONDS then return false end
    Scanner.Start()
    return true
end

function Scanner.Start()
    if Scanner.running then return end
    if not Scanner.Supported() then Scanner.Stop("unsupported"); return end
    if not ns.Compat.AuctionHouseOpen() then Scanner.Stop("closed"); return end
    resetBrowse(false)
    request("SendBrowseQuery", {searchString = "", sorts = {}, filters = {}})
    changed()
end

function Scanner.OnEvent(event)
    if event == "AUCTION_HOUSE_CLOSED" then
        if Scanner.running then Scanner.Stop("closed") end
        return
    end
    if not Scanner.running or Scanner.state ~= "browse" or not (Scanner.waiting or Scanner.passive) then return end
    if event == "AUCTION_HOUSE_BROWSE_FAILURE" then Scanner.Stop("failed"); return end
    if event ~= "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and event ~= "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then return end
    Scanner.waiting = nil
    Scanner.deadline = GetTime() + REQUEST_TIMEOUT
    -- GetBrowseResults is cumulative across pages.
    for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local key = result.itemKey
        if key and ns.IsNumber(result.minPrice) then
            local id = table.concat({key.itemID or 0, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0}, ":")
            if not Scanner.seen[id] then
                Scanner.seen[id] = true
                Scanner.results[#Scanner.results + 1] = {itemID = key.itemID, itemKey = key, minPrice = result.minPrice,
                    quantity = ns.IsNumber(result.totalQuantity) and result.totalQuantity or 1,
                    own = result.containsOwnerItem}
                Scanner.total = Scanner.total + 1
            end
        end
    end
    if C_AuctionHouse.HasFullBrowseResults() then
        startEvaluating(Scanner.results, "quick")
    elseif not Scanner.passive then
        request("RequestMoreBrowseResults")
        changed()
    else
        changed()   -- Auctionator asks for the next page itself
    end
end

function Scanner.Tick()
    if not Scanner.running then return end
    if Scanner.state == "evaluating" then evaluate(); return end
    if Scanner.deadline and GetTime() > Scanner.deadline then Scanner.Stop("timeout"); return end
    if not Scanner.pending then return end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    local pending = Scanner.pending
    Scanner.pending, Scanner.waiting = nil, true
    Scanner.deadline = GetTime() + REQUEST_TIMEOUT
    Scanner.ownQuery = true
    local ok = pcall(C_AuctionHouse[pending.name], unpack(pending.args))
    Scanner.ownQuery = false
    if not ok then Scanner.Stop("failed") end
end

-- An empty browse query with no filters: the whole-AH scan Auctionator also runs.
local function isWholeAHQuery(query)
    if type(query) ~= "table" or (query.searchString or "") ~= "" then return false end
    return not (query.filters and #query.filters > 0) and not (query.itemClassFilters and #query.itemClassFilters > 0)
end

-- Searches by others: Auctionator's whole-AH quick scan is adopted (its results are what a
-- quick scan needs); any other search replaces the browse results, so a quick scan stops.
function Scanner.InstallHooks()
    if Scanner.hooked or not Scanner.Supported() or not hooksecurefunc then return end
    Scanner.hooked = true
    hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
        if Scanner.ownQuery then return end
        Scanner.lastForeignSearch = GetTime()
        if isWholeAHQuery(query) then
            if not Scanner.running or Scanner.state == "browse" then
                resetBrowse(true)
                changed()
            end
        elseif Scanner.running and Scanner.state == "browse" then
            Scanner.Stop("interrupted")
        end
    end)
    for _, name in ipairs({"SendSearchQuery", "SearchForItemKeys", "SearchForFavorites", "SendSellSearchQuery"}) do
        if C_AuctionHouse[name] then
            hooksecurefunc(C_AuctionHouse, name, function()
                if Scanner.ownQuery then return end
                -- The AH lists favorites by itself when it opens; that isn't you searching.
                if name ~= "SearchForFavorites" then Scanner.lastForeignSearch = GetTime() end
                if Scanner.running and Scanner.state == "browse" and not Scanner.passive then
                    Scanner.Stop("interrupted")
                end
            end)
        end
    end
end

-- Opens Auctionator's shopping search for a row so you can buy with its buttons.
function Scanner.OpenInAuctionator(row)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.MultiSearchExact then
        ns.Print("Auctionator isn't loaded; search the AH for " .. row.name .. " yourself.")
        return
    end
    local ok, err = pcall(api.MultiSearchExact, ns.CALLER_ID, {row.name})
    if not ok then ns.Print("Auctionator search failed: " .. tostring(err)) end
end
