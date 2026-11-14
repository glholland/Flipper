-- AH to AH flips: items listed well below what they usually go for.
-- Built from the History summary (Auctionator's latest price and multi-day average), so it
-- is only as fresh as your last Auctionator scan. Flipper never buys: rows open Auctionator.
local _, ns = ...
local Deals = {}
ns.Deals = Deals

local MAX_PRICE_RATIO = 0.7      -- listed at 70% of the average or less
local MIN_DAYS_TRACKED = 5       -- the average needs a few days behind it
local MAX_DAYS_SINCE_SEEN = 1    -- the cheap listing was seen today or yesterday

-- History rows that are deals, each given `profit` (average after the AH cut, minus the
-- price now) and `daysTracked`. Sorting and caching are the History summary's.
function Deals.Rows()
    local minProfit = FlipperDB and FlipperDB.minFlipProfit or ns.DEFAULTS.minFlipProfit
    local rows = {}
    for _, row in ipairs(ns.History.Summary(nil)) do
        row.profit = nil
        if row.latest and row.average and row.lastSeen and row.lastSeen <= MAX_DAYS_SINCE_SEEN
            and (row.daysTracked or 0) >= MIN_DAYS_TRACKED and row.latest <= row.average * MAX_PRICE_RATIO then
            local profit = ns.Logic.NetAH(row.average, ns.AH_CUT) - row.latest
            if profit >= minProfit then
                row.profit = profit
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end
