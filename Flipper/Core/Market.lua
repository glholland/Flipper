-- How fast things sell.
--  * Market (everyone): full AH scans (C_AuctionHouse.ReplicateItems) are compared with the
--    previous one. Listings that vanish are classed as expired, cancelled or sold
--    (Logic.CompareSnapshots). The AH never reports other people's sales or names other
--    sellers, so "sold" is an estimate: the cheapest listings that vanish before they could
--    have expired.
--  * You: Journalator's statistics (if installed) count your own sales and failed auctions.
local _, ns = ...
local Market = {state = "idle"}
ns.Market = Market

local COOLDOWN = 15 * 60        -- Blizzard limits full scans; retail is 15 minutes
local MAX_GAP = 12 * 3600       -- after 12h every listing could have expired: nothing to learn
local WINDOW_DAYS = 14
local LOAD_WAIT = 8             -- seconds to wait for seller names to load

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

function Market.CooldownLeft()
    local last = db().lastScan
    return last and math.max(0, COOLDOWN - (time() - last)) or 0
end

function Market.Start()
    if not Market.Supported() then Market.state = "unsupported"; changed(); return end
    if not ns.Compat.AuctionHouseOpen() then Market.state = "closed"; changed(); return end
    if Market.state == "replicating" or Market.state == "reading" then return end
    local wait = Market.CooldownLeft()
    if wait > 0 then
        ns.Print(string.format("full scans are limited; next one in %d:%02d", math.floor(wait / 60), wait % 60))
        return
    end
    Market.state, Market.deadline, Market.startedAt = "replicating", GetTime() + 90, GetTime()
    Market.loaded, Market.total = 0, 0
    db().lastScan = time()
    C_AuctionHouse.ReplicateItems()
    changed()
end

-- Reads the replicate list into a snapshot. Returns nil while seller names are still loading.
local function readSnapshot(acceptPartial)
    local snapshot, pending = {}, 0
    for index = 0, C_AuctionHouse.GetNumReplicateItems() - 1 do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo =
            C_AuctionHouse.GetReplicateItemInfo(index)
        if not hasAllInfo then pending = pending + 1 end
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
    Market.total = C_AuctionHouse.GetNumReplicateItems()
    Market.loaded = Market.total - pending
    if pending > 0 and not acceptPartial then return nil end
    return snapshot
end

local function finish(snapshot)
    local store, now = db(), time()
    local auctions = 0
    for _ in pairs(snapshot) do auctions = auctions + 1 end
    if store.snapshot and store.snapshotAt and now - store.snapshotAt <= MAX_GAP then
        local elapsed = now - store.snapshotAt
        local result = ns.Logic.CompareSnapshots(store.snapshot, snapshot, elapsed)
        ns.Logic.AddObservation(store.stats, result, elapsed, today())
        Market.lastResult = result
        ns.Print(string.format("full scan done: %d items listed, compared with %d min ago.", auctions, math.floor(elapsed / 60)))
    else
        ns.Print(string.format("full scan done: %d items listed. Scan again in 15 minutes to 12 hours to estimate sales.", auctions))
    end
    store.snapshot, store.snapshotAt = snapshot, now
    -- Forget days outside the window.
    local oldest = today() - WINDOW_DAYS
    for day in pairs(store.stats.observed or {}) do if day < oldest then store.stats.observed[day] = nil end end
    for itemID, days in pairs(store.stats.items or {}) do
        for day in pairs(days) do if day < oldest then days[day] = nil end end
        if not next(days) then store.stats.items[itemID] = nil end
    end
    Market.state = "done"
    if ns.Vendors then ns.Vendors.Invalidate() end
    if ns.History then ns.History.Invalidate() end
    changed()
end

function Market.OnEvent(event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" and Market.state == "replicating" then
        Market.state, Market.readUntil = "reading", GetTime() + LOAD_WAIT
        changed()
    elseif event == "AUCTION_HOUSE_CLOSED" and (Market.state == "replicating" or Market.state == "reading") then
        Market.state = "closed"
        changed()
    end
end

function Market.Tick()
    if Market.state == "replicating" and GetTime() > Market.deadline then
        -- No answer means no scan happened: don't hold the next try to the cooldown.
        Market.state = "timeout"; db().lastScan = nil; changed()
    elseif Market.state == "reading" then
        if Market.nextRead and GetTime() < Market.nextRead then return end
        Market.nextRead = GetTime() + 1
        local snapshot = readSnapshot(GetTime() > Market.readUntil)
        if snapshot then finish(snapshot) end
    end
end

-- For the progress bar: fraction done (nil while unknown), label, seconds running.
function Market.Progress()
    if Market.state ~= "replicating" and Market.state ~= "reading" then return nil end
    local elapsed = GetTime() - (Market.startedAt or GetTime())
    if Market.state == "reading" and Market.total > 0 then
        return Market.loaded / Market.total,
            string.format("Full scan: loading auction details %d / %d", Market.loaded, Market.total), elapsed
    end
    return nil, "Full scan: waiting for the auction house", elapsed
end

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
