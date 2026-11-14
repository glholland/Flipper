-- A stand-in for the parts of the WoW client and Auctionator that Flipper's scan code uses.
-- Loaded into a fresh Lua 5.1 state before the addon files; returns a helper table `W` that
-- the scenarios in test_scans.lua use to drive time, the auction house and Auctionator.
local W = {}

------------------------------------------------------------------------
-- Clock and timers
------------------------------------------------------------------------
local EPOCH = 1794600000          -- wall-clock seconds at test start
W.elapsed = 0                     -- GetTime() value
local timers = {}

function GetTime() return W.elapsed end
function time(t)
    if type(t) == "table" then return os.time(t) end
    return EPOCH + math.floor(W.elapsed)
end
C_Timer = {After = function(seconds, fn) timers[#timers + 1] = {at = W.elapsed + seconds, fn = fn} end}

-- Moves time forward without ticking the addon (a long gap between AH visits).
function W.advance(seconds) W.elapsed = W.elapsed + seconds end

-- Runs the addon's 0.1 s tick `n` times, firing timers that come due.
function W.tick(n)
    for _ = 1, n or 1 do
        W.elapsed = W.elapsed + 0.1
        local due = {}
        for i = #timers, 1, -1 do
            if timers[i].at <= W.elapsed then due[#due + 1] = table.remove(timers, i) end
        end
        for _, t in ipairs(due) do t.fn() end
        W.ns.Scanner.Tick()
        W.ns.Market.Tick()
    end
end

------------------------------------------------------------------------
-- Globals the addon touches
------------------------------------------------------------------------
W.printed = {}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, text) W.printed[#W.printed + 1] = text end}

function hooksecurefunc(tbl, name, fn)
    if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
    local original = tbl[name]
    tbl[name] = function(...)
        local results = {original(...)}
        fn(...)
        return unpack(results)
    end
end

-- Item data: W.items[itemID] = {name, sellPrice}. Unknown items stay "uncached".
W.items = {}
C_Item = {
    GetItemInfo = function(id)
        local item = W.items[id]
        if not item then return nil end
        -- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sellPrice, classID
        return item[1], "item:" .. id, 1, 10, 1, "Trade Goods", "Misc", 20, "", 134400, item[2], 7
    end,
    RequestLoadItemDataByID = function() end,
}

AuctionHouseFrame = {shown = true, IsShown = function(self) return self.shown end}

------------------------------------------------------------------------
-- The auction house
------------------------------------------------------------------------
-- Full scan data: W.ah.listings = {{itemID, count, buyout, band}}.
-- Browse data: W.ah.browsePages = {{{itemID, minPrice, quantity, own}}, ...}.
W.ah = {}
local calls = {}
W.calls = calls

local function count(name) calls[name] = (calls[name] or 0) + 1 end

C_AuctionHouse = {
    ReplicateItems = function() count("ReplicateItems") end,
    GetNumReplicateItems = function() return #W.ah.listings end,
    GetReplicateItemInfo = function(index)
        local l = W.ah.listings[index + 1]
        -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement,
        -- buyout, bid, highBidder, bidderFull, owner, ownerFull, saleStatus, itemID, hasAllInfo
        return "x", 1, l[2], 1, true, 1, "", 0, 0, l[3], 0, nil, nil, nil, nil, 0, l[1], true
    end,
    GetReplicateItemTimeLeft = function(index) return W.ah.listings[index + 1][4] or 4 end,
    SendBrowseQuery = function(query) count("SendBrowseQuery"); W.ah.lastQuery = query end,
    RequestMoreBrowseResults = function() count("RequestMoreBrowseResults") end,
    GetBrowseResults = function()
        local results = {}
        for page = 1, W.ah.pagesDelivered do
            for _, r in ipairs(W.ah.browsePages[page]) do
                results[#results + 1] = {itemKey = {itemID = r[1], itemLevel = 0, itemSuffix = 0}, minPrice = r[2],
                    totalQuantity = r[3], containsOwnerItem = r[4] or false}
            end
        end
        return results
    end,
    HasFullBrowseResults = function() return W.ah.pagesDelivered >= #W.ah.browsePages end,
    IsThrottledMessageSystemReady = function() return true end,
    SendSearchQuery = function() count("SendSearchQuery") end,
    SearchForFavorites = function() count("SearchForFavorites") end,
    SearchForItemKeys = function() count("SearchForItemKeys") end,
    SendSellSearchQuery = function() count("SendSellSearchQuery") end,
}

-- The AH answering a full scan request.
function W.deliverReplicate() W.ns.Market.OnEvent("REPLICATE_ITEM_LIST_UPDATE") end

-- The AH sending the next page of browse results.
function W.deliverBrowsePage()
    W.ah.pagesDelivered = W.ah.pagesDelivered + 1
    W.ns.Scanner.OnEvent(W.ah.pagesDelivered == 1 and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
        or "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
end

function W.closeAH()
    AuctionHouseFrame.shown = false
    W.ns.Scanner.OnEvent("AUCTION_HOUSE_CLOSED")
    W.ns.Market.OnEvent("AUCTION_HOUSE_CLOSED")
end

------------------------------------------------------------------------
-- Auctionator (optional; W.installAuctionator() adds it)
------------------------------------------------------------------------
-- Mirrors the parts of Auctionator's full-scan frame Flipper uses: CanInitiate (15 minutes
-- since its own last scan, not in progress) and InitiateScan (stamps its clock, then calls
-- C_AuctionHouse.ReplicateItems).
function W.installAuctionator(options)
    options = options or {}
    local saved = {TimeOfLastReplicateScan = options.lastFull, TimeOfLastBrowseScan = options.lastSummary}
    local full = {inProgress = false, initiated = 0}
    function full:CanInitiate()
        return (saved.TimeOfLastReplicateScan == nil or time() - saved.TimeOfLastReplicateScan > 900) and not self.inProgress
    end
    function full:InitiateScan()
        if not self:CanInitiate() then return end
        self.initiated = self.initiated + 1
        saved.TimeOfLastReplicateScan, self.inProgress = time(), true
        C_AuctionHouse.ReplicateItems()
    end
    local summary = {doingFullScan = false}
    local config = {[ "autoscan_2" ] = options.autoscan or false}
    Auctionator = {
        SavedState = saved,
        State = {FullScanFrameRef = full, IncrementalScanFrameRef = summary},
        Config = {Options = {AUTOSCAN = "autoscan_2"}, Get = function(key) return config[key] end},
    }
    return Auctionator
end

-- Auctionator's own summary scan: the same empty browse query Flipper sends.
function W.auctionatorSummaryScan()
    Auctionator.State.IncrementalScanFrameRef.doingFullScan = true
    C_AuctionHouse.SendBrowseQuery({searchString = "", sorts = {}, filters = {}, itemClassFilters = {}})
end

------------------------------------------------------------------------
-- Fresh state for each scenario
------------------------------------------------------------------------
function W.reset()
    W.elapsed = W.elapsed + 100000       -- far from any earlier scenario's timestamps
    for i = #timers, 1, -1 do timers[i] = nil end
    for k in pairs(calls) do calls[k] = nil end
    W.printed = {}
    W.ah.listings, W.ah.browsePages, W.ah.pagesDelivered, W.ah.lastQuery = {}, {{}}, 0, nil
    AuctionHouseFrame.shown = true
    Auctionator = nil
    FlipperDB = W.ns.ApplyDefaults({}, W.ns.DEFAULTS)
    local S, M = W.ns.Scanner, W.ns.Market
    S.rows, S.state, S.total, S.deferred = {}, "idle", 0, 0
    S.running, S.passive, S.pending, S.waiting, S.queue = false, nil, nil, nil, nil
    S.lastForeignSearch, S.doneAt, S.summary, S.source = nil, nil, nil, nil
    M.state, M.snapshot, M.summary, M.byAuctionator, M.starting = "idle", nil, nil, nil, nil
end

return W
