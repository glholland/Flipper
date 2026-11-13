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

-- Value of one craft's output after the cut, cost of its reagents at AH prices.
-- Reagents without a price are listed in `missing` and make profit nil.
function Logic.CraftMargin(recipe, priceFn, cut)
    local result = {missing = {}}
    local outputPrice = Logic.NetAH(priceFn(recipe.output), cut)
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
function Logic.ReagentValue(recipe, reagentID, priceFn, cut)
    local outputPrice = Logic.NetAH(priceFn(recipe.output), cut)
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
