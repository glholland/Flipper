-- What a piece of gear disenchants into, and what that is worth.
-- Tables and Forever rules adapted from Disenchantry's DisenchantResults.lua and
-- ForecastPolicy.lua (MIT, see NOTICE). Forever uses the original-era tables.
local _, ns = ...
local Disenchant = {}
ns.Disenchant = Disenchant

-- Uncommon: min/max ilvl, dust/essence/shard IDs, armor dust/essence %, weapon dust/essence %,
-- dust min/max, essence min/max. The shard (if any) takes the remaining chance, one at a time.
local UNCOMMON = {
    {5, 15, 10940, 10938, nil, 80, 20, 20, 80, 1, 2, 1, 2},
    {16, 20, 10940, 10939, 10978, 75, 20, 20, 75, 2, 3, 1, 2},
    {21, 25, 10940, 10998, 10978, 75, 15, 15, 75, 4, 6, 1, 2},
    {26, 30, 11083, 11082, 11084, 75, 20, 20, 75, 1, 2, 1, 2},
    {31, 35, 11083, 11134, 11138, 75, 20, 20, 75, 2, 5, 1, 2},
    {36, 40, 11137, 11135, 11139, 75, 20, 20, 75, 1, 2, 1, 2},
    {41, 45, 11137, 11174, 11177, 75, 20, 20, 75, 2, 5, 1, 2},
    {46, 50, 11176, 11175, 11178, 75, 20, 20, 75, 1, 2, 1, 2},
    {51, 55, 11176, 16202, 14343, 75, 20, 22, 75, 2, 5, 1, 2},
    {56, 60, 16204, 16203, 14344, 75, 20, 22, 75, 1, 2, 1, 2},
    {61, 65, 16204, 16203, 14344, 75, 20, 22, 75, 2, 5, 2, 3},
}
local RARE = {
    {1, 25, 10978}, {26, 30, 11084}, {31, 35, 11138}, {36, 40, 11139},
    {41, 45, 11177}, {46, 50, 11178}, {51, 55, 14343}, {56, 80, 14344, 20725},
}
local EPIC = {
    {40, 45, 11177, 2, 4}, {46, 50, 11178, 2, 4}, {51, 55, 14343, 2, 4},
    {56, 60, 20725, 1, 1}, {61, 88, 20725, 1, 2},
}
-- Enchanter-made wands can't be disenchanted.
local EXCLUDED = {
    [11287] = true, [11288] = true, [11289] = true, [11290] = true,
    [247789] = true, [249144] = true, [249234] = true, [249232] = true, [249237] = true, [249385] = true,
}

local function outcome(id, chance, low, high)
    return {itemID = id, chance = chance, min = low or 1, max = high or low or 1}
end
local function find(rows, level)
    for _, row in ipairs(rows) do
        if level >= row[1] and level <= row[2] then return row end
    end
end

-- Forever's own rare items (IDs 200000+) don't follow the old tables; Disenchantry's
-- estimates by item level, marked approximate.
local function foreverRare(level, weapon)
    if level < 5 or level > 99 then return nil end
    if level <= 15 then
        return {outcome(10940, weapon and 20 or 80, 2, 3), outcome(10938, weapon and 80 or 20, 2, 3)}
    elseif level <= 20 then
        return {outcome(10940, weapon and 20 or 75, 3, 4), outcome(10939, weapon and 75 or 20, 2, 3), outcome(10978, 5, 2)}
    end
    for _, step in ipairs({{25, 10978}, {30, 11084}, {35, 11138}, {40, 11139}, {45, 11177}, {50, 11178}, {55, 14343}}) do
        if level <= step[1] then return {outcome(step[2], 100)} end
    end
    return {outcome(14344, 99.5), outcome(20725, 0.5)}
end

-- Possible results for gear of this quality, base item level and class (2 weapon, 4 armor):
-- {{itemID, chance (percent), min, max}}, or nil when it can't be disenchanted or isn't known.
-- Pure: no client calls, so the tests can check it.
function Disenchant.Outcomes(itemID, quality, level, classID)
    if EXCLUDED[itemID] or (classID ~= 2 and classID ~= 4) or not level or level <= 0 then return nil end
    local weapon = classID == 2
    if quality == 2 then
        local row = find(UNCOMMON, level)
        if not row then return nil end
        local dust, essence = row[weapon and 8 or 6], row[weapon and 9 or 7]
        local essenceID = row[4]
        -- Forever: uncommon weapons of item level 21-30 give Greater Magic Essence.
        if weapon and level >= 21 and level <= 30 then essenceID = 10939 end
        local results = {outcome(row[3], dust, row[10], row[11]), outcome(essenceID, essence, row[12], row[13])}
        if row[5] then results[#results + 1] = outcome(row[5], 100 - dust - essence) end
        return results
    elseif quality == 3 then
        if itemID and itemID >= 200000 then return foreverRare(level, weapon) end
        local row = find(RARE, level)
        if not row then return nil end
        if row[4] then return {outcome(row[3], 99.5), outcome(row[4], 0.5)} end
        return {outcome(row[3], 100)}
    elseif quality == 4 then
        local row = find(EPIC, level)
        if row then return {outcome(row[3], 100, row[4], row[5])} end
    end
end

-- Expected value of one disenchant: chance x average quantity x price, summed. nil when no
-- result has a price. `priceFn(itemID)` should already be net of the AH cut.
function Disenchant.ExpectedValue(outcomes, priceFn)
    local total, priced = 0, false
    for _, result in ipairs(outcomes or {}) do
        local price = priceFn(result.itemID)
        if ns.IsNumber(price) then
            total = total + price * result.chance / 100 * (result.min + result.max) / 2
            priced = true
        end
    end
    return priced and math.floor(total) or nil
end

-- Client side: outcomes for an item ID, from the item's cached info.
function Disenchant.ForItem(itemID)
    if not ns.IsNumber(itemID) or not C_Item or not C_Item.GetItemInfo then return nil end
    local name, _, quality, level, _, _, _, _, equipSlot, _, _, classID = C_Item.GetItemInfo(itemID)
    if not name or not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_BAG" then return nil end
    return Disenchant.Outcomes(itemID, quality, level, classID)
end

-- What disenchanting one is worth after selling the materials on the AH, or nil.
function Disenchant.Value(itemID)
    return Disenchant.ExpectedValue(Disenchant.ForItem(itemID), function(id)
        return ns.Logic.NetAH(ns.Prices.Fair(id), ns.AH_CUT)
    end)
end

function Disenchant.Known()
    local professions = FlipperCharDB and FlipperCharDB.professions
    return professions and professions.Enchanting ~= nil or false
end
