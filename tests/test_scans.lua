-- Scenario tests for the scan code (Core/Scanner.lua, Core/Market.lua) against the fake
-- client and fake Auctionator in fake_wow.lua. Run with: python tests/run_tests.py
local W, ns = ...
W.ns = ns
local Scanner, Market = ns.Scanner, ns.Market
local failures, passed = {}, 0
local scenario = "?"

local function eq(name, got, want)
    if got == want then passed = passed + 1
    else failures[#failures + 1] = string.format("[%s] %s: got %s, want %s", scenario, name, tostring(got), tostring(want)) end
end
local function calls(name) return W.calls[name] or 0 end
local function rowFor(itemID)
    for _, row in ipairs(Scanner.rows) do if row.itemID == itemID then return row end end
end
local function runUntilIdle(limit)
    for _ = 1, limit or 200 do
        if not Scanner.running and not Market.Busy() then return end
        W.tick()
    end
end

-- Items: {name, vendor sell price}
W.items[100] = {"Copper Ore", 25}
W.items[200] = {"Linen Cloth", 13}
W.items[300] = {"Sword", 500}

-- Every listing: {itemID, count, buyout for the whole stack, time-left band}
local LISTINGS = {
    {300, 1, 300, 4},     -- 300 each, below the 500 vendor price
    {300, 2, 1200, 4},    -- 600 each, above it
    {100, 20, 200, 4},    -- 10 each, below 25
    {200, 5, 100, 4},     -- 20 each, above 13
}

ns.Scanner.InstallHooks()
ns.Market.InstallHooks()

------------------------------------------------------------------------
scenario = "full scan, no Auctionator"
W.reset()
W.ah.listings = LISTINGS
eq("starts", Market.Start(), true)
eq("one request to the AH", calls("ReplicateItems"), 1)
eq("waiting for the AH", Market.state, "waiting")
eq("busy", Market.Busy(), true)
eq("cooldown started", Market.CooldownLeft() > 890, true)
W.deliverReplicate()
eq("reading", Market.state, "reading")
runUntilIdle()
eq("done", Market.state, "done")
eq("snapshot saved", FlipperDB.market.snapshot[300] ~= nil, true)
eq("first scan says sales start next time", Market.summary:find("start with the next") ~= nil, true)
eq("sell-to-vendor rows from the full scan", #Scanner.rows, 2)
eq("sword: only the cheap listing counts", rowFor(300) and rowFor(300).quantity, 1)
eq("sword profit", rowFor(300) and rowFor(300).profit, 200)
eq("ore quantity below vendor", rowFor(100) and rowFor(100).quantity, 20)
eq("linen not a flip", rowFor(200), nil)
eq("rows came from the full scan", Scanner.source, "full")

scenario = "cooldown"
eq("second scan refused within 15 minutes", Market.Start(), false)
eq("no second request", calls("ReplicateItems"), 1)

scenario = "second full scan two hours later"
W.advance(7200)
W.ah.listings = {
    {300, 2, 1200, 4},    -- the 300 sword is gone; the 600 ones are still up
    {200, 5, 100, 4},     -- ore all gone
}
eq("allowed again", Market.Start(), true)
W.deliverReplicate()
runUntilIdle()
local day = ns.Day()
local stats = FlipperDB.market.stats
eq("ore counted as sold", stats.items[100] and stats.items[100][day] and stats.items[100][day][1], 20)
eq("cheapest sword counted as sold", stats.items[300] and stats.items[300][day] and stats.items[300][day][1], 1)
eq("two hours watched", stats.observed[day] >= 7200 and stats.observed[day] <= 7201, true)
eq("summary says sales updated", Market.summary:find("Sales estimates updated") ~= nil, true)

------------------------------------------------------------------------
scenario = "reading is spread over ticks"
W.reset()
local many = {}
for i = 1, 1500 do many[i] = {100, 1, 30, 4} end
W.ah.listings = many
Market.Start()
W.deliverReplicate()
W.tick()
eq("first tick reads one batch", Market.loaded, 600)
eq("still reading", Market.state, "reading")
runUntilIdle()
eq("all read", Market.loaded, 1500)

------------------------------------------------------------------------
scenario = "full scan through Auctionator"
W.reset()
W.ah.listings = LISTINGS
local auctionator = W.installAuctionator()
eq("starts", Market.Start(), true)
eq("went through Auctionator's frame", auctionator.State.FullScanFrameRef.initiated, 1)
eq("one request to the AH", calls("ReplicateItems"), 1)
eq("counted as Flipper's scan", Market.byAuctionator, false)
eq("Auctionator's clock stamped", auctionator.SavedState.TimeOfLastReplicateScan, time())
W.deliverReplicate()
runUntilIdle()
eq("Flipper read it", Market.state, "done")

------------------------------------------------------------------------
scenario = "cooldown on Auctionator's clock"
W.reset()
W.installAuctionator({lastFull = time() - 300})
eq("10 minutes left", Market.CooldownLeft(), 600)
eq("refused", Market.Start(), false)
eq("no request", calls("ReplicateItems"), 0)

------------------------------------------------------------------------
scenario = "Auctionator starts its own full scan"
W.reset()
W.ah.listings = LISTINGS
W.installAuctionator()
Auctionator.State.FullScanFrameRef:InitiateScan()
eq("Flipper noticed", Market.state, "waiting")
eq("labelled as Auctionator's", Market.byAuctionator, true)
eq("Flipper's clock follows", Market.CooldownLeft() > 890, true)
eq("Flipper won't start a second one", Market.Start(), false)
eq("still one request", calls("ReplicateItems"), 1)
W.deliverReplicate()
runUntilIdle()
eq("Flipper used the results", FlipperDB.market.snapshot ~= nil, true)
eq("and built sell-to-vendor rows", #Scanner.rows, 2)

------------------------------------------------------------------------
scenario = "AH closes mid full scan"
W.reset()
W.ah.listings = LISTINGS
Market.Start()
W.closeAH()
eq("stopped", Market.state, "closed")
eq("not busy", Market.Busy(), false)
eq("cooldown kept (the request went out)", Market.CooldownLeft() > 0, true)
eq("no snapshot saved", FlipperDB.market.snapshot, nil)

------------------------------------------------------------------------
scenario = "AH never answers"
W.reset()
Market.Start()
W.tick(910)
eq("timed out", Market.state, "timeout")
eq("cooldown released", Market.CooldownLeft(), 0)

------------------------------------------------------------------------
scenario = "quick scan"
W.reset()
W.ah.browsePages = {
    {{300, 300, 3}, {100, 10, 30, true}},     -- sword below vendor; ore below too, but it's yours
    {{200, 2, 4}},                            -- linen 2 vs 13 vendor
}
Scanner.Start()
W.tick()
eq("one browse query", calls("SendBrowseQuery"), 1)
eq("not treated as Auctionator's", Scanner.passive, nil)
W.deliverBrowsePage()
W.tick()
eq("asked for page 2", calls("RequestMoreBrowseResults"), 1)
W.deliverBrowsePage()
runUntilIdle()
eq("done", Scanner.state, "done")
eq("two flips", #Scanner.rows, 2)
eq("own listing skipped", rowFor(100), nil)
eq("quantity is what's listed", rowFor(300) and rowFor(300).quantity, 3)
eq("summary says sales unchanged", Scanner.summary and Scanner.summary:find("Sales estimates unchanged") ~= nil, true)

------------------------------------------------------------------------
scenario = "Auctionator's summary scan is adopted"
W.reset()
W.ah.browsePages = {{{300, 300, 3}}}
W.installAuctionator()
W.auctionatorSummaryScan()
eq("Flipper follows along", Scanner.running, true)
eq("as a passive reader", Scanner.passive, true)
W.deliverBrowsePage()
runUntilIdle()
eq("finished", Scanner.state, "done")
eq("Flipper sent no query of its own", calls("SendBrowseQuery"), 1)
eq("found the sword", rowFor(300) ~= nil, true)

scenario = "Auctionator's summary scan joins a running quick scan"
W.reset()
W.ah.browsePages = {{{300, 300, 3}}, {{200, 2, 4}}}
W.installAuctionator()
Scanner.Start()
W.tick()
W.auctionatorSummaryScan()
eq("not interrupted", Scanner.state, "browse")
eq("now following Auctionator", Scanner.passive, true)
W.deliverBrowsePage()
W.tick()
eq("doesn't page on its own", calls("RequestMoreBrowseResults"), 0)

scenario = "another search stops a quick scan"
W.reset()
W.ah.browsePages = {{{300, 300, 3}}, {{200, 2, 4}}}
Scanner.Start()
W.tick()
C_AuctionHouse.SendSearchQuery()
eq("interrupted", Scanner.state, "interrupted")

------------------------------------------------------------------------
scenario = "auto quick scan"
W.reset()
local opened = GetTime()
eq("off by default", Scanner.MaybeAutoScan(opened), false)
FlipperDB.autoQuickScan = true
C_AuctionHouse.SearchForFavorites()     -- the AH lists favorites by itself on open
eq("runs when on", Scanner.MaybeAutoScan(opened), true)

W.reset()
FlipperDB.autoQuickScan = true
opened = GetTime()
W.tick()
C_AuctionHouse.SendSearchQuery()
eq("skipped after you searched", Scanner.MaybeAutoScan(opened), false)

W.reset()
FlipperDB.autoQuickScan = true
W.installAuctionator({autoscan = true})
eq("skipped when Auctionator autoscans", Scanner.MaybeAutoScan(GetTime()), false)

W.reset()
FlipperDB.autoQuickScan = true
W.installAuctionator({lastSummary = time() - 60})
eq("skipped when prices are a minute old", Scanner.MaybeAutoScan(GetTime()), false)

W.reset()
FlipperDB.autoQuickScan = true
Market.Start()
eq("skipped during a full scan", Scanner.MaybeAutoScan(GetTime()), false)

W.reset()
FlipperDB.autoQuickScan = true
W.closeAH()
eq("skipped with the AH closed", Scanner.MaybeAutoScan(GetTime()), false)

return passed, failures
