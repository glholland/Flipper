-- Adds Flipper's verdict to item tooltips. Mainline tooltips go through TooltipDataProcessor.
-- Normally: one verdict line (keep / craft / auction / vendor, with the reason) and the
-- recipes your own professions use the item in. Hold Shift while hovering for the rest:
-- prices, where a vendor sells it, sales estimates and every recipe that uses it.
local _, ns = ...
local Tooltip = {}
ns.Tooltip = Tooltip
local Money = ns.Money

local TAG = "|cff4ade80Flipper|r "
local GREY = {0.6, 0.6, 0.6}
local OWN_USES_SHOWN, ALL_USES_SHOWN = 3, 20

-- Recipes that take an item, from Data/CraftDB.lua (all of Blizzard's Forever recipes,
-- trainer-taught ones and enchants included). Trainer recipes have no skill level in
-- Blizzard's data (skill 0).
local usedIn
local function recipesUsing(itemID)
    if not usedIn then
        usedIn = {}
        for _, entry in ipairs(ns.CraftDB or {}) do
            local flat = entry[5] or {}
            for i = 1, #flat - 1, 2 do
                local list = usedIn[flat[i]] or {}
                usedIn[flat[i]] = list
                list[#list + 1] = {profession = entry[1], name = entry[2], skill = entry[3] or 0, qty = flat[i + 1]}
            end
        end
    end
    return usedIn[itemID] or {}
end

local function knownRecipeNames()
    local known = {}
    for _, recipe in ns.Recipes.All() do
        if recipe.name then known[recipe.name:lower()] = true end
    end
    return known
end

-- Splits an item's uses into your professions' and everyone else's, yours sorted by skill.
-- Each of your uses gets .known and .reach (known, or its recipe item's skill is within yours).
local function sortedUses(itemID)
    local mine = FlipperCharDB and FlipperCharDB.professions or {}
    local known = knownRecipeNames()
    local own, others, knownCount = {}, {}, 0
    for _, use in ipairs(recipesUsing(itemID)) do
        local skill = mine[use.profession]
        if skill then
            use.known = known[use.name:lower()] or false
            use.reach = use.known or (use.skill > 0 and skill >= use.skill)
            use.tooHard = use.skill > skill
            if use.known then knownCount = knownCount + 1 end
            own[#own + 1] = use
        else
            others[#others + 1] = use
        end
    end
    local function order(a, b)
        if a.profession ~= b.profession then return a.profession < b.profession end
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end
    table.sort(own, function(a, b)
        if a.known ~= b.known then return a.known end
        return order(a, b)
    end)
    table.sort(others, order)
    return own, others, knownCount
end

-- Auctionator already prints the vendor and auction price in the same tooltip; with it
-- loaded Flipper says what to do and leaves the numbers to Auctionator.
local function pricesShownElsewhere()
    return Auctionator and Auctionator.API and Auctionator.API.v1 and true or false
end

-- "Keep for Tailoring (3 known, 6 recipes)", "Craft Silk Bag: 3s each", "Auction it", ...
local function verdict(advice, own, knownCount)
    local quiet = pricesShownElsewhere()
    local price
    if quiet then price = advice.action == "ah" and "auction" or advice.action == "vendor" and "vendor" or nil
    elseif advice.action == "ah" then price = "AH " .. Money.Format(advice.perUnit)
    elseif advice.action == "vendor" then price = "vendor " .. Money.Format(advice.perUnit) end
    if advice.action == "craft" then
        return "Craft " .. advice.craftName .. ": " .. Money.Format(advice.perUnit) .. " each"
    end
    if advice.action == "disenchant" then
        return "Disenchant it: ~" .. Money.Format(advice.perUnit) .. " in materials"
    end
    if #own > 0 then
        local professions, seen = {}, {}
        for _, use in ipairs(own) do
            if not seen[use.profession] then seen[use.profession] = true; professions[#professions + 1] = use.profession end
        end
        local counts = knownCount > 0 and string.format("%d known, %d %s", knownCount, #own, #own == 1 and "recipe" or "recipes")
            or string.format("%d %s", #own, #own == 1 and "recipe" or "recipes")
        return "Keep for " .. table.concat(professions, ", ") .. " (" .. counts .. ")" .. (price and ("  -  or " .. price) or "")
    end
    if advice.action == "ah" then
        return quiet and "Auction it" or ("Auction it: " .. Money.Format(advice.perUnit) .. " each after the cut")
    end
    if advice.action == "vendor" then
        return quiet and "Vendor it" or ("Vendor it: " .. Money.Format(advice.perUnit) .. " each")
    end
end

local function useLine(tooltip, use)
    local r, g, b = unpack(GREY)
    if use.reach then r, g, b = 0.29, 0.87, 0.5
    elseif use.tooHard then r, g, b = 0.97, 0.44, 0.44
    elseif use.reach ~= nil then r, g, b = 1, 1, 1 end
    local label = use.profession .. (use.skill > 0 and (" " .. use.skill) or "")
    tooltip:AddLine(string.format("  %s: %s x%d%s", label, use.name, use.qty, use.known and " (known)" or ""), r, g, b)
end

local function addDetails(tooltip, itemID)
    local parts = {}
    local ah = ns.Logic.NetAH(ns.Prices.Fair(itemID), ns.AH_CUT)
    local vendor = ns.Prices.Vendor(itemID)
    if ah then parts[#parts + 1] = "AH after cut " .. Money.Format(ah) end
    if vendor and vendor > 0 and not pricesShownElsewhere() then parts[#parts + 1] = "vendor pays " .. Money.Format(vendor) end
    if #parts > 0 then tooltip:AddLine("  " .. table.concat(parts, ", "), unpack(GREY)) end
    local buy = ns.Vendors.BuyPrice(itemID)
    if buy then
        local seller = ns.Vendors.Sellers(itemID)[1]
        tooltip:AddLine("  Sold by vendors: " .. Money.Format(buy) .. (seller and (" at " .. ns.Vendors.Describe(seller)) or ""), unpack(GREY))
    end
    local perDay, through, hours = ns.Market.Rate(itemID)
    if perDay then
        local text = "  Market: ~" .. ns.Market.FormatRate(perDay):gsub("/d", " sold/day")
        if through then text = text .. string.format(", %d%% of listings sell", math.floor(through * 100 + 0.5)) end
        tooltip:AddLine(text .. string.format(" (%.0fh watched)", hours or 0), unpack(GREY))
    end
    local sold, failed = ns.Market.Own((ns.Compat.ItemInfo(itemID)))
    if sold then
        tooltip:AddLine(string.format("  You: %d sold, %d didn't (%d%%)", sold, failed,
            math.floor(sold / (sold + failed) * 100 + 0.5)), unpack(GREY))
    end
end

-- For gear: what it disenchants into and the enchants those materials go into.
-- "Disenchants into Small Glowing Shard" then "  Enchanting 100: Enchant Bracer - Lesser
-- Strength (1 Small Glowing Shard)". Shown to enchanters, and to everyone with Shift held.
local function enchantUses(outcomes)
    local mine = FlipperCharDB and FlipperCharDB.professions or {}
    local known = knownRecipeNames()
    local skill = mine.Enchanting
    local uses, seen = {}, {}
    for _, result in ipairs(outcomes) do
        for _, use in ipairs(recipesUsing(result.itemID)) do
            if use.profession == "Enchanting" and not seen[use.name] then
                seen[use.name] = true
                uses[#uses + 1] = {profession = use.profession, name = use.name, skill = use.skill, qty = use.qty,
                    material = result.itemID, known = known[use.name:lower()] or false}
                local u = uses[#uses]
                if skill then
                    u.reach = u.known or (u.skill > 0 and skill >= u.skill)
                    u.tooHard = u.skill > skill
                end
            end
        end
    end
    table.sort(uses, function(a, b)
        if a.known ~= b.known then return a.known end
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end)
    return uses
end

local function addDisenchantLines(tooltip, outcomes, shift)
    local names = {}
    for _, result in ipairs(outcomes) do
        local name = ns.Compat.ItemInfo(result.itemID)
        if name then
            local chance = result.chance < 100 and string.format(" (%s%%)", result.chance) or ""
            names[#names + 1] = name .. chance
        end
    end
    if #names == 0 then return end
    tooltip:AddLine("  Disenchants into " .. table.concat(names, ", "), 0.75, 0.52, 0.99)
    local uses = enchantUses(outcomes)
    local limit = math.min(#uses, shift and ALL_USES_SHOWN or OWN_USES_SHOWN)
    for i = 1, limit do
        local use = uses[i]
        local r, g, b = 1, 1, 1
        if use.reach then r, g, b = 0.29, 0.87, 0.5 elseif use.tooHard then r, g, b = 0.97, 0.44, 0.44 end
        local label = "Enchanting" .. (use.skill > 0 and (" " .. use.skill) or "")
        local material = ns.Compat.ItemInfo(use.material) or "?"
        tooltip:AddLine(string.format("  %s: %s (%d %s)%s", label, use.name, use.qty, material,
            use.known and " (known)" or ""), r, g, b)
    end
    if #uses > limit then
        tooltip:AddLine(string.format("  +%d more enchants%s", #uses - limit, shift and "" or " (hover with Shift held)"),
            unpack(GREY))
    end
end

local function addLines(tooltip, data)
    if not FlipperDB or not FlipperDB.tooltip or not data then return end
    local itemID = data.id
    if not ns.IsNumber(itemID) or not tooltip.AddLine then return end
    local advice = ns.Bags.Advice(itemID)
    local own, others, knownCount = sortedUses(itemID)
    local text = verdict(advice, own, knownCount)
    local shift = IsShiftKeyDown()
    local outcomes = (shift or ns.Disenchant.Known()) and ns.Disenchant.ForItem(itemID) or nil
    -- Nothing to say: no line at all (other professions' uses still show with Shift).
    if not text and not outcomes and not (shift and #others > 0) then return end
    tooltip:AddLine(TAG .. (text or "No use for your professions"), 1, 1, 1)
    if outcomes then addDisenchantLines(tooltip, outcomes, shift) end
    if shift then addDetails(tooltip, itemID) end
    local shown = 0
    for i = 1, math.min(#own, shift and ALL_USES_SHOWN or OWN_USES_SHOWN) do useLine(tooltip, own[i]); shown = shown + 1 end
    if shift then
        for i = 1, math.min(#others, ALL_USES_SHOWN - shown) do useLine(tooltip, others[i]); shown = shown + 1 end
    end
    local hidden = #own + #others - shown
    if hidden > 0 then
        tooltip:AddLine(string.format("  +%d more %s%s", hidden, hidden == 1 and "use" or "uses",
            shift and "" or " (hover with Shift held)"), unpack(GREY))
    end
end

function Tooltip.Install()
    if Tooltip.installed then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            -- Never let a pricing hiccup break the game's tooltip.
            pcall(addLines, tooltip, data)
        end)
        Tooltip.installed = true
    end
end
