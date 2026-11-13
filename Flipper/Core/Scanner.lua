-- Browses the whole auction house once and lists items whose cheapest listing is below
-- what a vendor pays. Browse paging and interruption handling adapted from Disenchantry's
-- Core/AuctionScan.lua (MIT, see NOTICE). Flipper never buys: rows open Auctionator's search.
local _, ns = ...
local Scanner = {rows = {}, state = "idle", total = 0, deferred = 0}
ns.Scanner = Scanner

local LOAD_WAIT_SECONDS = 5     -- how long to wait for uncached item info before giving up on it
local REQUEST_TIMEOUT = 30

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

function Scanner.Stop(reason)
    Scanner.running, Scanner.pending, Scanner.waiting = false, nil, nil
    Scanner.state = reason or "stopped"
    changed()
end

local function request(name, ...)
    Scanner.pending = {name = name, args = {...}}
    Scanner.deadline = GetTime() + REQUEST_TIMEOUT
end

-- Turns browse results into flip rows. Results whose item info isn't cached are kept
-- for another pass until LOAD_WAIT_SECONDS passes.
local function evaluate()
    local minProfit = FlipperDB and FlipperDB.minFlipProfit or ns.DEFAULTS.minFlipProfit
    local remaining = {}
    for _, result in ipairs(Scanner.queue) do
        local itemID = result.itemKey and result.itemKey.itemID
        local name, _, quality, icon, sellPrice = ns.Compat.ItemInfo(itemID)
        if not name then
            remaining[#remaining + 1] = result
        elseif not result.containsOwnerItem then
            local profit = ns.Logic.EvaluateFlip(result.minPrice, ns.IsNumber(sellPrice) and sellPrice or 0, minProfit)
            if profit then
                Scanner.rows[#Scanner.rows + 1] = {
                    itemID = itemID, itemKey = result.itemKey, name = name, icon = icon, quality = quality,
                    minPrice = result.minPrice, vendor = sellPrice, profit = profit,
                    quantity = ns.IsNumber(result.totalQuantity) and result.totalQuantity or 1,
                }
            end
        end
    end
    Scanner.queue = remaining
    if #remaining == 0 or GetTime() > Scanner.loadDeadline then
        Scanner.deferred = #remaining
        table.sort(Scanner.rows, function(a, b) return a.profit * a.quantity > b.profit * b.quantity end)
        Scanner.running, Scanner.state = false, "done"
    end
    changed()
end

function Scanner.Start()
    if Scanner.running then return end
    if not Scanner.Supported() then Scanner.Stop("unsupported"); return end
    if not ns.Compat.AuctionHouseOpen() then Scanner.Stop("closed"); return end
    Scanner.rows, Scanner.results, Scanner.seen, Scanner.total, Scanner.deferred = {}, {}, {}, 0, 0
    Scanner.running, Scanner.state = true, "browse"
    request("SendBrowseQuery", {searchString = "", sorts = {}, filters = {}})
    changed()
end

function Scanner.OnEvent(event)
    if event == "AUCTION_HOUSE_CLOSED" then
        if Scanner.running then Scanner.Stop("closed") end
        return
    end
    if not Scanner.running or Scanner.state ~= "browse" or not Scanner.waiting then return end
    if event == "AUCTION_HOUSE_BROWSE_FAILURE" then Scanner.Stop("failed"); return end
    if event ~= "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and event ~= "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then return end
    Scanner.waiting = nil
    -- GetBrowseResults is cumulative across pages.
    for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local key = result.itemKey
        if key and ns.IsNumber(result.minPrice) then
            local id = table.concat({key.itemID or 0, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0}, ":")
            if not Scanner.seen[id] then
                Scanner.seen[id] = true
                Scanner.results[#Scanner.results + 1] = result
                Scanner.total = Scanner.total + 1
            end
        end
    end
    if C_AuctionHouse.HasFullBrowseResults() then
        Scanner.state, Scanner.queue, Scanner.loadDeadline = "evaluating", Scanner.results, GetTime() + LOAD_WAIT_SECONDS
        evaluate()
    else
        request("RequestMoreBrowseResults")
        changed()
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

-- Someone else (the default UI, Auctionator) started a search: our snapshot is no longer ours.
function Scanner.InstallHooks()
    if Scanner.hooked or not Scanner.Supported() or not hooksecurefunc then return end
    Scanner.hooked = true
    for _, name in ipairs({"SendBrowseQuery", "SendSearchQuery", "SearchForItemKeys", "SearchForFavorites",
        "SendSellSearchQuery", "RequestMoreBrowseResults"}) do
        if C_AuctionHouse[name] then
            hooksecurefunc(C_AuctionHouse, name, function()
                if Scanner.running and Scanner.state == "browse" and not Scanner.ownQuery then
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
