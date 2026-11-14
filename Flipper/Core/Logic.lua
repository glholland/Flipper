-- Pure pricing rules: no client calls, so tests/run_tests.py can exercise them offline.
local _, ns = ...
local Logic = {}
ns.Logic = Logic

local function num(v) return ns.IsNumber(v) and v or nil end

-- What a sale at `price` puts in your pocket after the AH cut.
function Logic.NetAH(price, cut)
    price = num(price)
    if not price then return nil end
    return math.floor(price * (1 - (cut or ns.AH_CUT)))
end

-- Profit per unit from buying at `minPrice` and selling to a vendor, or nil.
-- nil sellPrice means the item info isn't loaded yet; 0 means vendors won't buy it.
function Logic.EvaluateFlip(minPrice, sellPrice, minProfit)
    minPrice, sellPrice = num(minPrice), num(sellPrice)
    if not minPrice or not sellPrice or minPrice <= 0 or sellPrice <= 0 then return nil end
    local profit = sellPrice - minPrice
    if profit < (minProfit or 1) then return nil end
    return profit
end

local function averageQuantity(recipe)
    local low = num(recipe.qtyMin) or 1
    local high = num(recipe.qtyMax) or low
    return (low + high) / 2
end

-- A price you can expect to sell at. The cheapest listing is often one optimistic seller
-- (a single 50g listing for a 66s item), so when it is more than twice the multi-day
-- average, trust the average. Cheaper-than-average listings are kept: that's the real market.
function Logic.FairPrice(latest, mean)
    latest, mean = num(latest), num(mean)
    if latest and latest <= 0 then latest = nil end
    if mean and mean <= 0 then mean = nil end
    if not latest then return mean end
    if mean and latest > 2 * mean then return mean end
    return latest
end

-- Profit per unit from buying at a vendor and selling on the AH after the cut, or nil
-- when it doesn't clear `minProfit` or a `minMargin` share of the vendor price.
function Logic.VendorFlip(vendorEach, ahFair, cut, minProfit, minMargin)
    vendorEach = num(vendorEach)
    local net = Logic.NetAH(ahFair, cut)
    if not vendorEach or vendorEach <= 0 or not net then return nil end
    local profit = net - vendorEach
    if profit < (minProfit or 1) or profit < vendorEach * (minMargin or 0) then return nil end
    return math.floor(profit)
end

-- Value of one craft's output after the cut, cost of its reagents at AH prices.
-- Reagents without a price are listed in `missing` and make profit nil.
-- `sellFn` prices the output (defaults to priceFn); pass Prices.Fair to value what you sell
-- at a realistic price while buying reagents at today's price.
-- `vendorFn` (optional) is what a vendor pays for the output: when that beats the AH after
-- the cut, the craft is valued at the vendor price and result.sellTo is "vendor".
local function outputValue(recipe, priceFn, cut, sellFn, vendorFn)
    local ah = Logic.NetAH((sellFn or priceFn)(recipe.output), cut)
    local vendor = vendorFn and num(vendorFn(recipe.output))
    if vendor and vendor > 0 and (not ah or vendor >= ah) then return vendor, "vendor" end
    return ah, ah and "ah" or nil
end

function Logic.CraftMargin(recipe, priceFn, cut, sellFn, vendorFn)
    local result = {missing = {}}
    local outputPrice
    outputPrice, result.sellTo = outputValue(recipe, priceFn, cut, sellFn, vendorFn)
    result.value = outputPrice and math.floor(outputPrice * averageQuantity(recipe)) or nil
    local cost = 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        local p = num(priceFn(reagent[1]))
        if p then cost = cost + p * reagent[2]
        else result.missing[#result.missing + 1] = reagent[1] end
    end
    result.cost = cost
    if result.value and #result.missing == 0 then result.profit = result.value - cost end
    return result
end

-- What one unit of `reagentID` is worth when turned into this recipe's output:
-- (craft value - cost of the other reagents) / how many of it the craft uses.
function Logic.ReagentValue(recipe, reagentID, priceFn, cut, sellFn, vendorFn)
    local outputPrice = outputValue(recipe, priceFn, cut, sellFn, vendorFn)
    if not outputPrice then return nil end
    local used, others = 0, 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        if reagent[1] == reagentID then
            used = used + reagent[2]
        else
            local p = num(priceFn(reagent[1]))
            if not p then return nil end
            others = others + p * reagent[2]
        end
    end
    if used <= 0 then return nil end
    return math.floor((outputPrice * averageQuantity(recipe) - others) / used)
end

-- How many crafts it takes for a recipe bought at `recipePrice` to pay for itself, or nil
-- when crafting it doesn't make money.
function Logic.Payback(recipePrice, profitPerCraft)
    recipePrice, profitPerCraft = num(recipePrice), num(profitPerCraft)
    if not recipePrice or not profitPerCraft or profitPerCraft <= 0 then return nil end
    return math.max(1, math.ceil(recipePrice / profitPerCraft))
end

-- Expands a RecipeDB entry {profession, skill, name, output, qtyMin, qtyMax, {id, qty, ...}}
-- into the recipe shape CraftMargin takes.
function Logic.RecipeFromDB(entry)
    local reagents, flat = {}, entry[7] or {}
    for i = 1, #flat - 1, 2 do reagents[#reagents + 1] = {flat[i], flat[i + 1]} end
    return {profession = entry[1], skill = entry[2], name = entry[3], output = entry[4],
        qtyMin = entry[5], qtyMax = entry[6], reagents = reagents}
end

------------------------------------------------------------------------
-- Sales estimates from two full AH snapshots
------------------------------------------------------------------------
-- snapshot[itemID][unitPrice] = {q = quantity, tl = shortest time-left band}
-- Bands (Enum.AuctionHouseTimeLeftBand): 0 <30m, 1 30m-2h, 2 2h-12h, 3 12h-48h.
-- The client doesn't name other sellers, so listings are compared by item and price only.
Logic.BAND_MIN_SECONDS = {[0] = 0, [1] = 1800, [2] = 7200, [3] = 43200}

-- What happened to listings missing from `now`, `elapsed` seconds after `prev`:
-- {[itemID] = {sold, expired, cancelled}}. Rules, most cautious first:
--  * it could have run out of time (elapsed >= the least time its band had left) -> expired
--  * a cheaper listing from `prev` is still up -> cancelled: buyers take the cheapest
--    first, so a dearer one that vanished was pulled (usually to relist lower)
--  * otherwise -> sold. A seller who pulls the cheapest listing to repost it even lower
--    also lands here, so read "sold" as an upper estimate.
function Logic.CompareSnapshots(prev, now, elapsed)
    local result = {}
    for itemID, prices in pairs(prev) do
        local current = now[itemID] or {}
        -- Cheapest earlier price that still has stock.
        local floor
        for price in pairs(prices) do
            if current[price] and current[price].q > 0 and (not floor or price < floor) then floor = price end
        end
        for price, entry in pairs(prices) do
            local gone = entry.q - (current[price] and current[price].q or 0)
            if gone > 0 then
                local r = result[itemID] or {sold = 0, expired = 0, cancelled = 0}
                result[itemID] = r
                if elapsed >= (Logic.BAND_MIN_SECONDS[entry.tl] or 0) then
                    r.expired = r.expired + gone
                elseif floor and price > floor then
                    r.cancelled = r.cancelled + gone
                else
                    r.sold = r.sold + gone
                end
            end
        end
    end
    return result
end

-- Merges an older snapshot[itemID][seller][unitPrice] into the seller-free shape.
function Logic.FlattenSnapshot(snapshot)
    local flat = {}
    local function merge(prices, price, entry)
        local have = prices[price]
        if have then have.q, have.tl = have.q + entry.q, math.min(have.tl, entry.tl)
        else prices[price] = {q = entry.q, tl = entry.tl} end
    end
    for itemID, inner in pairs(snapshot or {}) do
        local prices = {}
        flat[itemID] = prices
        for key, value in pairs(inner) do
            if type(key) == "string" then
                for price, entry in pairs(value) do merge(prices, price, entry) end
            else
                merge(prices, key, value)
            end
        end
    end
    return flat
end

-- Folds one comparison into rolling per-day stats:
-- stats = {observed = {[day] = seconds}, items = {[itemID] = {[day] = {s, e, c}}}}
function Logic.AddObservation(stats, result, elapsed, day)
    stats.observed = stats.observed or {}
    stats.items = stats.items or {}
    stats.observed[day] = (stats.observed[day] or 0) + elapsed
    for itemID, r in pairs(result) do
        local days = stats.items[itemID] or {}
        stats.items[itemID] = days
        local d = days[day] or {0, 0, 0}
        days[day] = {d[1] + r.sold, d[2] + r.expired, d[3] + r.cancelled}
    end
    return stats
end

-- Estimated units sold per day and sell-through (sold / everything that left the AH) over
-- the last `window` days, or nil without at least an hour of observation.
function Logic.SalesRate(stats, itemID, today, window)
    if not stats or not stats.observed then return nil end
    local observed, sold, ended = 0, 0, 0
    for day = today - window + 1, today do
        observed = observed + (stats.observed[day] or 0)
        local d = stats.items and stats.items[itemID] and stats.items[itemID][day]
        if d then sold = sold + d[1]; ended = ended + d[1] + d[2] + d[3] end
    end
    if observed < 3600 then return nil end
    return sold / (observed / 86400), ended > 0 and sold / ended or nil, observed
end

-- Sorts rows in place by getter(row). Rows whose value is nil always go last, whichever
-- direction; equal values fall back to row.name so the order is stable between refreshes.
function Logic.SortRows(rows, getter, descending)
    table.sort(rows, function(a, b)
        local va, vb = getter(a), getter(b)
        if va == nil or vb == nil then
            if (va == nil) ~= (vb == nil) then return vb == nil end
        elseif va ~= vb then
            if type(va) == "string" then va, vb = va:lower(), vb:lower() end
            if va ~= vb then
                if descending then return va > vb end
                return va < vb
            end
        end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

-- Picks the best thing to do with one unit of an item.
-- opts = {ah=market price|nil, vendor=sell price|nil, crafts={{name, perUnit}}, cut}
-- Ties go to the vendor: instant and no listing risk.
function Logic.BestUse(opts)
    local best = {action = "none", perUnit = 0}
    local vendor = num(opts.vendor)
    if vendor and vendor > 0 then best = {action = "vendor", perUnit = vendor} end
    local ah = Logic.NetAH(opts.ah, opts.cut)
    if ah and ah > best.perUnit then best = {action = "ah", perUnit = ah} end
    for _, craft in ipairs(opts.crafts or {}) do
        local value = num(craft.perUnit)
        if value and value > best.perUnit then
            best = {action = "craft", perUnit = value, craftName = craft.name}
        end
    end
    return best
end
