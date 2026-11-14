-- Market prices from TSM or Auctionator, with a 60 second cache.
-- Adapted from Disenchantry's PriceProviders.lua (MIT, see NOTICE).
local _, ns = ...
local Prices = {}
ns.Prices = Prices

local cache = {}
local CACHE_SECONDS = 60
local MAX_AGE_DAYS = 7

local adapters = {
    {
        label = "TSM",
        present = function()
            return TSM_API and type(TSM_API.GetCustomPriceValue) == "function"
        end,
        quote = function(id)
            return TSM_API.GetCustomPriceValue("DBMarket", "i:" .. id)
        end,
    },
    {
        label = "Auctionator",
        present = function()
            local api = Auctionator and Auctionator.API and Auctionator.API.v1
            return api and type(api.GetAuctionPriceByItemID) == "function"
        end,
        quote = function(id)
            -- Auctionator keeps the last price it ever saw. One that hasn't been seen for
            -- over a week isn't a price you can buy or sell at.
            local age = Auctionator.API.v1.GetAuctionAgeByItemID
                and Auctionator.API.v1.GetAuctionAgeByItemID(ns.CALLER_ID, id)
            if Auctionator.API.v1.GetAuctionAgeByItemID and (not ns.IsNumber(age) or age > MAX_AGE_DAYS) then
                return nil
            end
            return Auctionator.API.v1.GetAuctionPriceByItemID(ns.CALLER_ID, id)
        end,
    },
}

-- Last known AH price for one unit, or nil.
function Prices.AH(itemID)
    if not ns.IsNumber(itemID) then return nil end
    local now = GetTime()
    local hit = cache[itemID]
    if hit and hit.expires > now then return hit.value end
    local value
    for _, adapter in ipairs(adapters) do
        local okPresent, present = pcall(adapter.present)
        if okPresent and present then
            local ok, quote = pcall(adapter.quote, itemID)
            if ok and ns.IsNumber(quote) and quote > 0 then value = quote; break end
        end
    end
    cache[itemID] = {value = value, expires = now + CACHE_SECONDS}
    return value
end

-- Auctionator's multi-day mean (its "average" setting, default 21 days), or nil.
local meanCache = {}
function Prices.Mean(itemID)
    if not ns.IsNumber(itemID) then return nil end
    local now = GetTime()
    local hit = meanCache[itemID]
    if hit and hit.expires > now then return hit.value end
    local value
    local db = Auctionator and Auctionator.Database
    if db and type(db.GetMeanPrice) == "function" then
        local days = 21
        local config = Auctionator.Config
        if config and config.Get and config.Options and config.Options.AUCTION_MEAN_DAYS_LIMIT then
            local ok, d = pcall(config.Get, config.Options.AUCTION_MEAN_DAYS_LIMIT)
            if ok and ns.IsNumber(d) and d >= 1 then days = math.floor(d) end
        end
        local ok, mean = pcall(db.GetMeanPrice, db, tostring(itemID), days)
        if ok and ns.IsNumber(mean) and mean > 0 then value = mean end
    end
    meanCache[itemID] = {value = value, expires = now + CACHE_SECONDS}
    return value
end

-- What you can realistically sell one unit for (see Logic.FairPrice).
function Prices.Fair(itemID)
    return ns.Logic.FairPrice(Prices.AH(itemID), Prices.Mean(itemID))
end

-- How many days Auctionator has a price for (0 without Auctionator): one or two sightings
-- is a listing, not a market.
function Prices.DaysSeen(itemID)
    local db = Auctionator and Auctionator.Database and Auctionator.Database.db
    local entry = type(db) == "table" and db[tostring(itemID)]
    local days = 0
    if type(entry) == "table" then for _ in pairs(entry.h or {}) do days = days + 1 end end
    return days
end

-- Cheapest way to get one unit: the AH or a vendor that sells it. Thread, dye and vials
-- are vendor goods; pricing them from the AH inflates craft costs or leaves them unpriced.
local buyCache = {}
function Prices.Buy(itemID)
    if not ns.IsNumber(itemID) then return nil end
    local now = GetTime()
    local hit = buyCache[itemID]
    if hit and hit.expires > now then return hit.value end
    local value = Prices.AH(itemID)
    local vendor = ns.Vendors and ns.Vendors.BuyPrice(itemID)
    if ns.IsNumber(vendor) and vendor > 0 and (not value or vendor < value) then value = vendor end
    buyCache[itemID] = {value = value, expires = now + CACHE_SECONDS}
    return value
end

-- What a vendor pays for one unit: 0 if they won't buy it, nil while uncached.
-- `noRequest`: don't ask the server for uncached items (big lists).
function Prices.Vendor(itemID, noRequest)
    local name, _, _, _, sellPrice = ns.Compat.ItemInfo(itemID, noRequest)
    if not name then return nil end
    return ns.IsNumber(sellPrice) and sellPrice or 0
end

function Prices.Source()
    for _, adapter in ipairs(adapters) do
        local ok, present = pcall(adapter.present)
        if ok and present then return adapter.label end
    end
end

function Prices.ClearCache() cache, meanCache, buyCache = {}, {}, {} end
