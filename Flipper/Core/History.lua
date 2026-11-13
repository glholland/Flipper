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

local RECENT_DAYS = 14   -- the summary lists items Auctionator has seen in this many days

-- Every item with recent Auctionator prices (plus anything Flipper has seen sell):
-- {itemID, name, latest, average, change, listed, daysTracked, lastSeen, perDay}.
-- `search` (optional) keeps items whose name contains it, case-insensitive.
-- Building the summary touches thousands of items, so it is cached until Invalidate()
-- (new prices, a full scan) or the search changes. Item names that weren't cached are filled
-- in later for the rows on screen only (Window's fill step).
local cache = {}
function History.Invalidate() cache = {} end

function History.Summary(search)
    search = search and search ~= "" and search:lower() or nil
    if cache.rows and cache.search == search then return cache.rows end
    local rows = History.BuildSummary(search)
    cache.rows, cache.search = rows, search
    return rows
end

function History.BuildSummary(search)
    local rows, seen = {}, {}
    local today = ns.Day()
    local db = Auctionator and Auctionator.Database and Auctionator.Database.db
    local function add(itemID, entry)
        if seen[itemID] then return end
        seen[itemID] = true
        local name, _, quality, icon = ns.Compat.ItemInfo(itemID, true)
        if search and not (name and name:lower():find(search, 1, true)) then return end
        local row = {itemID = itemID, name = name or ("item " .. itemID), quality = quality, icon = icon,
            needsInfo = not name, perDay = (ns.Market.Rate(itemID))}
        if entry then
            local days, lastDay = 0, nil
            for day in pairs(entry.h or {}) do
                day = tonumber(day)
                if day then days = days + 1; if not lastDay or day > lastDay then lastDay = day end end
            end
            row.latest = tonumber(entry.m)
            row.average = ns.Prices.Mean(itemID)
            row.daysTracked, row.lastSeen = days, lastDay and (today - lastDay) or nil
            row.listed = lastDay and entry.a and tonumber(entry.a[lastDay] or entry.a[tostring(lastDay)]) or nil
            if row.latest and row.average and row.average > 0 then row.change = row.latest / row.average - 1 end
        end
        rows[#rows + 1] = row
    end
    if type(db) == "table" then
        for key, entry in pairs(db) do
            local itemID = type(key) == "string" and tonumber(key:match("^(%d+)$"))
            if itemID and type(entry) == "table" then
                local recent = false
                for day in pairs(entry.h or {}) do
                    if tonumber(day) and tonumber(day) > today - RECENT_DAYS then recent = true; break end
                end
                if recent then add(itemID, entry) end
            end
        end
    end
    local s = stats()
    for itemID in pairs(s and s.items or {}) do add(itemID, db and db[tostring(itemID)]) end
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
