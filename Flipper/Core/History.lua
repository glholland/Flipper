-- History page data: day by day for one item (Auctionator's price history + Flipper's sales
-- estimates), and a summary of every item Flipper has watched.
local _, ns = ...
local History = {}
ns.History = History

local DAYS_SHOWN = 30

local function stats() return FlipperDB and FlipperDB.market and FlipperDB.market.stats end

-- Auctionator's per-day {minSeen, maxSeen, available}, keyed by day number.
local function auctionatorDays(itemID)
    local db = Auctionator and Auctionator.Database
    if not db or type(db.GetPriceHistory) ~= "function" then return {} end
    local ok, list = pcall(db.GetPriceHistory, db, tostring(itemID))
    local days = {}
    for _, entry in ipairs(ok and list or {}) do
        local day = tonumber(entry.rawDay)
        if day then days[day] = entry end
    end
    return days
end

-- {{day, date, low, high, listed, sold, expired, cancelled, watched}} newest first, for days
-- that have any data in the last DAYS_SHOWN days.
function History.ItemDays(itemID)
    local prices = auctionatorDays(itemID)
    local s = stats() or {}
    local itemDays = s.items and s.items[itemID] or {}
    local today = ns.Day()
    local rows = {}
    for day = today, today - DAYS_SHOWN + 1, -1 do
        local p, d = prices[day], itemDays[day]
        local watched = s.observed and s.observed[day]
        if p or d then
            rows[#rows + 1] = {
                day = day, name = date("%a %b %d", ns.DayStart(day) + 43200),
                low = p and tonumber(p.minSeen), high = p and tonumber(p.maxSeen), listed = p and tonumber(p.available),
                sold = d and d[1] or (watched and 0 or nil), expired = d and d[2] or (watched and 0 or nil),
                cancelled = d and d[3] or (watched and 0 or nil), watched = watched and watched / 3600 or nil,
            }
        end
    end
    return rows
end

-- One row per item Flipper has seen leave the AH: totals over the stats window.
function History.Summary()
    local s = stats()
    local rows = {}
    if not s or not s.items then return rows end
    local today, window = ns.Day(), ns.Market.WINDOW_DAYS
    for itemID, days in pairs(s.items) do
        local sold, expired, cancelled = 0, 0, 0
        for day, d in pairs(days) do
            if day > today - window then sold, expired, cancelled = sold + d[1], expired + d[2], cancelled + d[3] end
        end
        if sold + expired + cancelled > 0 then
            local name, _, quality, icon = ns.Compat.ItemInfo(itemID)
            local ended = sold + expired + cancelled
            rows[#rows + 1] = {itemID = itemID, name = name or ("item " .. itemID), quality = quality, icon = icon,
                sold = sold, expired = expired, cancelled = cancelled, through = sold / ended,
                perDay = (ns.Market.Rate(itemID))}
        end
    end
    return rows
end

-- Hours watched over the stats window, for the status line.
function History.HoursWatched()
    local s = stats()
    if not s or not s.observed then return 0 end
    local total, today = 0, ns.Day()
    for day, seconds in pairs(s.observed) do
        if day > today - ns.Market.WINDOW_DAYS then total = total + seconds end
    end
    return total / 3600
end
