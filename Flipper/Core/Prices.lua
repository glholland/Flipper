-- Market prices from TSM or Auctionator, with a 60 second cache.
-- Adapted from Disenchantry's PriceProviders.lua (MIT, see NOTICE).
local _, ns = ...
local Prices = {}
ns.Prices = Prices

local cache = {}
local CACHE_SECONDS = 60

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

-- What a vendor pays for one unit: 0 if they won't buy it, nil while uncached.
function Prices.Vendor(itemID)
    local name, _, _, _, sellPrice = ns.Compat.ItemInfo(itemID)
    if not name then return nil end
    return ns.IsNumber(sellPrice) and sellPrice or 0
end

function Prices.Source()
    for _, adapter in ipairs(adapters) do
        local ok, present = pcall(adapter.present)
        if ok and present then return adapter.label end
    end
end

function Prices.ClearCache() cache, meanCache = {}, {} end
