-- Full scans and how fast things sell.
--  * Market (everyone): a full scan (C_AuctionHouse.ReplicateItems) lists every auction. Each
--    one is compared with the previous one: listings that vanish are classed as expired,
--    cancelled or sold (Logic.CompareSnapshots). The AH never reports other people's sales or
--    names other sellers, so "sold" is an estimate.
--  * You: Journalator's statistics (if installed) count your own sales and failed auctions.
-- Full scans are shared with Auctionator: Flipper starts them through Auctionator's own
-- full-scan frame when it can (one scan feeds both addons and both keep the same cooldown),
-- and reads any full scan Auctionator starts by itself.
local _, ns = ...
local Market = {state = "idle"}
ns.Market = Market

local COOLDOWN = 15 * 60        -- the server allows one full scan per 15 minutes
local MAX_GAP = 12 * 3600       -- after 12h every listing could have expired: nothing to learn
local WINDOW_DAYS = 14
local ANSWER_WAIT = 90          -- seconds to wait for the AH to answer a full scan
local ROWS_PER_TICK = 600       -- listings read per 0.1 s tick, so reading doesn't freeze the game

-- Version 2: Auctionator's day numbers. Version 3: sales are judged by price, not by
-- seller (the client never names other sellers). Version 4: time-left bands are 1-4, not
-- 0-3 (version 3 counted listings with 2-12h left as unable to expire). Older stats are discarded.
local STATS_VERSION = 4

local function db()
    FlipperDB.market = FlipperDB.market or {stats = {}}
    local store = FlipperDB.market
    if store.version ~= STATS_VERSION then
        store.stats, store.version = {}, STATS_VERSION
        if store.snapshot then store.snapshot = ns.Logic.FlattenSnapshot(store.snapshot) end
    end
    return store
end
function Market.Migrate() db() end

local function today() return ns.Day() end
Market.WINDOW_DAYS = WINDOW_DAYS

local function changed() if Market.OnChanged then Market.OnChanged() end end

function Market.Supported()
    return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
        and C_AuctionHouse.GetReplicateItemInfo and true or false
end

------------------------------------------------------------------------
-- Auctionator
------------------------------------------------------------------------

local function auctionatorFullScan()
    local state = Auctionator and Auctionator.State
    return state and state.FullScanFrameRef
end

-- True while Auctionator runs either of its scans.
function Market.AuctionatorScanning()
    local state = Auctionator and Auctionator.State
    local full = state and state.FullScanFrameRef
    local summary = state and state.IncrementalScanFrameRef
    return (full and full.inProgress) and true or (summary and summary.doingFullScan) and true or false
end

-- Auctionator's saved scan times (time() values), or nil.
function Market.AuctionatorTimes()
    local saved = Auctionator and Auctionator.SavedState
    if type(saved) ~= "table" then return nil, nil end
    local full, summary = saved.TimeOfLastReplicateScan, saved.TimeOfLastBrowseScan
    return ns.IsNumber(full) and full or nil, ns.IsNumber(summary) and summary or nil
end

-- Whether Auctionator is set to scan by itself when the AH opens.
function Market.AuctionatorAutoscans()
    local config = Auctionator and Auctionator.Config
    if not config or not config.Get or not config.Options or not config.Options.AUTOSCAN then return false end
    local ok, on = pcall(config.Get, config.Options.AUTOSCAN)
    return ok and on and true or false
end

------------------------------------------------------------------------
-- Cooldown and state
------------------------------------------------------------------------

-- Seconds until a full scan is allowed: the later of Flipper's and Auctionator's clocks.
function Market.CooldownLeft()
    local last = db().lastScan or 0
    local theirs = Market.AuctionatorTimes()
    if theirs and theirs > last then last = theirs end
    return math.max(0, COOLDOWN - (time() - last))
end

function Market.Busy()
    return Market.state == "waiting" or Market.state == "reading"
end

-- When the last full scan finished (time()), or nil.
function Market.LastFullScan()
    return FlipperDB and FlipperDB.market and FlipperDB.market.snapshotAt
end

-- Called whenever ReplicateItems runs, whoever called it.
local function replicateStarted()
    if Market.Busy() then return end
    Market.state, Market.deadline, Market.startedAt = "waiting", GetTime() + ANSWER_WAIT, GetTime()
    Market.loaded, Market.total = 0, 0
    Market.byAuctionator = not Market.starting
    db().lastScan = time()
    changed()
end

function Market.InstallHooks()
    if Market.hooked or not Market.Supported() or not hooksecurefunc then return end
    Market.hooked = true
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", replicateStarted)
end

-- Starts a full scan if one is allowed. Returns false (and says why) when it isn't.
function Market.Start()
    if not Market.Supported() then Market.state = "unsupported"; changed(); return false end
    if not ns.Compat.AuctionHouseOpen() then return false end
    if Market.Busy() or Market.AuctionatorScanning() then return false end
    local wait = Market.CooldownLeft()
    if wait > 0 then
        ns.Print(string.format("full scans are limited to one per 15 minutes; next in %d:%02d", math.floor(wait / 60), wait % 60))
        return false
    end
    Market.InstallHooks()
    Market.starting = true
    local frame = auctionatorFullScan()
    local ok = false
    if frame and frame.InitiateScan and frame.CanInitiate and frame:CanInitiate() then
        ok = pcall(frame.InitiateScan, frame)
    end
    if not ok then pcall(C_AuctionHouse.ReplicateItems) end
    Market.starting = false
    if not Market.Busy() then replicateStarted() end   -- no hook: record it ourselves
    Market.byAuctionator = false
    return true
end

------------------------------------------------------------------------
-- Reading the listings, a few hundred per tick
------------------------------------------------------------------------

local function beginReading()
    Market.state, Market.cursor, Market.snapshot = "reading", 0, {}
    Market.total = C_AuctionHouse.GetNumReplicateItems() or 0
    Market.loaded = 0
    changed()
end

local function readSome()
    local snapshot, last = Market.snapshot, math.min(Market.total, Market.cursor + ROWS_PER_TICK) - 1
    for index = Market.cursor, last do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
            C_AuctionHouse.GetReplicateItemInfo(index)
        if ns.IsNumber(itemID) and ns.IsNumber(count) and count > 0 and ns.IsNumber(buyout) and buyout > 0 then
            local band = C_AuctionHouse.GetReplicateItemTimeLeft and C_AuctionHouse.GetReplicateItemTimeLeft(index) or 1
            local unit = math.floor(buyout / count)
            local prices = snapshot[itemID] or {}
            snapshot[itemID] = prices
            local entry = prices[unit]
            if entry then
                entry.q = entry.q + count
                entry.tl = math.min(entry.tl, band)
            else
                prices[unit] = {q = count, tl = band}
            end
        end
    end
    Market.cursor = last + 1
    Market.loaded = Market.cursor
    return Market.cursor >= Market.total
end

local function finish(snapshot)
    local store, now = db(), time()
    local items = 0
    for _ in pairs(snapshot) do items = items + 1 end
    local hadPrevious = store.snapshot and store.snapshotAt and now - store.snapshotAt <= MAX_GAP
    if hadPrevious then
        local elapsed = now - store.snapshotAt
        local result = ns.Logic.CompareSnapshots(store.snapshot, snapshot, elapsed)
        ns.Logic.AddObservation(store.stats, result, elapsed, today())
        Market.lastResult = result
    end
    store.snapshot, store.snapshotAt = snapshot, now
    -- Forget days outside the window.
    local oldest = today() - WINDOW_DAYS
    for day in pairs(store.stats.observed or {}) do if day < oldest then store.stats.observed[day] = nil end end
    for itemID, days in pairs(store.stats.items or {}) do
        for day in pairs(days) do if day < oldest then days[day] = nil end end
        if not next(days) then store.stats.items[itemID] = nil end
    end
    Market.state, Market.snapshot = "done", nil
    Market.summary = string.format("Full scan done: %d auctions of %d items. %s", Market.total, items,
        hadPrevious and "Sales estimates updated." or "Sales estimates start with the next full scan (15 min to 12 h from now).")
    if ns.Vendors then ns.Vendors.Invalidate() end
    if ns.History then ns.History.Invalidate() end
    -- The same listings tell what sells below vendor price.
    if ns.Scanner and ns.Scanner.FromSnapshot then ns.Scanner.FromSnapshot(snapshot) end
    ns.Print(Market.summary)
    if ns.Window and ns.Window.Notice then ns.Window.Notice(Market.summary) end
    changed()
end

function Market.OnEvent(event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" and Market.state == "waiting" then
        beginReading()
    elseif event == "AUCTION_HOUSE_CLOSED" and Market.Busy() then
        -- The request was sent, so the server's 15 minutes have started regardless.
        Market.state, Market.snapshot = "closed", nil
        changed()
    end
end

function Market.Tick()
    if Market.state == "waiting" and GetTime() > Market.deadline then
        -- No answer means no scan happened: don't hold the next try to the cooldown.
        Market.state = "timeout"; db().lastScan = nil; changed()
    elseif Market.state == "reading" then
        if readSome() then finish(Market.snapshot) end
    end
end

-- For the progress bar: fraction done (nil while unknown), label, seconds running.
function Market.Progress()
    if not Market.Busy() then return nil end
    local elapsed = GetTime() - (Market.startedAt or GetTime())
    local who = Market.byAuctionator and "Auctionator's full scan" or "Full scan"
    if Market.state == "reading" and Market.total > 0 then
        return Market.loaded / Market.total,
            string.format("%s: reading auctions %d / %d", who, Market.loaded, Market.total), elapsed
    end
    return nil, who .. ": waiting for the auction house", elapsed
end

------------------------------------------------------------------------
-- Sales rates
------------------------------------------------------------------------

-- Estimated units sold per day, sell-through (0-1) and hours observed, or nil.
function Market.Rate(itemID)
    local store = FlipperDB and FlipperDB.market
    if not store or store.version ~= STATS_VERSION or not ns.IsNumber(itemID) then return nil end
    local perDay, through, observed = ns.Logic.SalesRate(store.stats, itemID, today(), WINDOW_DAYS)
    return perDay, through, observed and observed / 3600
end

-- Your own results from Journalator: sold, failed (expired or cancelled). nil without data.
function Market.Own(itemName)
    local api = Journalator and Journalator.API and Journalator.API.v1
    if type(itemName) ~= "string" or not api or not api.GetRealmSuccessCountByItemName then return nil end
    local okS, sold = pcall(api.GetRealmSuccessCountByItemName, ns.CALLER_ID, itemName)
    local okF, failed = pcall(api.GetRealmFailureCountByItemName, ns.CALLER_ID, itemName)
    sold, failed = okS and sold or 0, okF and failed or 0
    if sold == 0 and failed == 0 then return nil end
    return sold, failed
end

function Market.FormatRate(perDay)
    if not perDay then return "|cff9ca3af-|r" end
    if perDay >= 10 then return string.format("%.0f/d", perDay) end
    return string.format("%.1f/d", perDay)
end
