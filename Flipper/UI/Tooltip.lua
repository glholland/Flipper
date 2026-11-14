-- Adds Flipper's verdict to item tooltips. Mainline tooltips go through TooltipDataProcessor.
local _, ns = ...
local Tooltip = {}
ns.Tooltip = Tooltip
local Money = ns.Money

local LABEL = {ah = "Auction it", vendor = "Vendor it", craft = "Craft it"}
local addVendorLine

local function addLines(tooltip, data)
    if not FlipperDB or not FlipperDB.tooltip or not data then return end
    local itemID = data.id
    if not ns.IsNumber(itemID) or not tooltip.AddLine then return end
    local advice = ns.Bags.Advice(itemID)
    if advice.action == "none" then return end
    local ah = ns.Logic.NetAH(ns.Prices.Fair(itemID), ns.AH_CUT)
    local vendor = ns.Prices.Vendor(itemID)
    local parts = {}
    if ah then parts[#parts + 1] = "AH " .. Money.Format(ah) end
    if vendor and vendor > 0 then parts[#parts + 1] = "Vendor " .. Money.Format(vendor) end
    tooltip:AddLine("|cff4ade80Flipper|r " .. table.concat(parts, "  "), 1, 1, 1)
    local verdict = LABEL[advice.action]
    if advice.action == "craft" then verdict = verdict .. " (" .. advice.craftName .. ")" end
    tooltip:AddLine("  Best: " .. verdict .. " " .. Money.Format(advice.perUnit) .. " each", 0.8, 0.8, 0.8)
    addVendorLine(tooltip, itemID)
end

-- "Vendor: 1s 50c at Name, Zone (x, y)" for items a vendor sells.
addVendorLine = function(tooltip, itemID)
    local buy = ns.Vendors.BuyPrice(itemID)
    if not buy then return end
    local seller = ns.Vendors.Sellers(itemID)[1]
    tooltip:AddLine("  Vendor: " .. Money.Format(buy) .. (seller and (" at " .. ns.Vendors.Describe(seller)) or ""), 0.8, 0.8, 0.8)
end

-- "Sells ~3.2/day (70% of listings sell)" and "You: 12 sold, 3 didn't".
local function addSalesLines(tooltip, data)
    if not FlipperDB or not FlipperDB.tooltip or not data or not ns.IsNumber(data.id) or not tooltip.AddLine then return end
    local perDay, through, hours = ns.Market.Rate(data.id)
    if perDay then
        local text = "  Market: ~" .. ns.Market.FormatRate(perDay):gsub("/d", " sold/day")
        if through then text = text .. string.format(", %d%% of listings sell", math.floor(through * 100 + 0.5)) end
        tooltip:AddLine(text .. string.format(" (%.0fh watched)", hours or 0), 0.8, 0.8, 0.8)
    end
    local name = ns.Compat.ItemInfo(data.id)
    local sold, failed = ns.Market.Own(name)
    if sold then
        tooltip:AddLine(string.format("  You: %d sold, %d didn't (%d%%)", sold, failed,
            math.floor(sold / (sold + failed) * 100 + 0.5)), 0.8, 0.8, 0.8)
    end
end

-- "Tailoring 125: Silk Bag x3" for every recipe that takes this item, from Data/CraftDB.lua
-- (all of Blizzard's Forever recipes, trainer-taught ones and enchants included).
-- Your own professions come first. Green: you know it, or have the skill its recipe item
-- asks for. Red: your profession, but not enough skill. Grey: someone else's profession.
-- Trainer recipes have no skill level in Blizzard's data, so they show none.
local USED_IN_SHOWN, USED_IN_SHIFT = 5, 20
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
    return usedIn[itemID]
end

local function knownRecipeNames()
    local known = {}
    for _, recipe in ns.Recipes.All() do
        if recipe.name then known[recipe.name:lower()] = true end
    end
    return known
end

local function addUsedInLines(tooltip, data)
    if not FlipperDB or not FlipperDB.tooltip or not data or not ns.IsNumber(data.id) or not tooltip.AddLine then return end
    local uses = recipesUsing(data.id)
    if not uses then return end
    local mine = FlipperCharDB and FlipperCharDB.professions or {}
    table.sort(uses, function(a, b)
        local am, bm = mine[a.profession] and 1 or 0, mine[b.profession] and 1 or 0
        if am ~= bm then return am > bm end
        if a.profession ~= b.profession then return a.profession < b.profession end
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end)
    local known = knownRecipeNames()
    local limit = IsShiftKeyDown() and USED_IN_SHIFT or USED_IN_SHOWN
    tooltip:AddLine("|cff4ade80Flipper|r Used in " .. #uses .. (#uses == 1 and " recipe" or " recipes"), 1, 1, 1)
    for i = 1, math.min(#uses, limit) do
        local use = uses[i]
        local skill = mine[use.profession]
        local isKnown = known[use.name:lower()]
        local r, g, b = 0.6, 0.6, 0.6
        if isKnown or (skill and use.skill > 0 and skill >= use.skill) then r, g, b = 0.29, 0.87, 0.5
        elseif skill and use.skill > skill then r, g, b = 0.97, 0.44, 0.44
        elseif skill then r, g, b = 1, 1, 1 end
        local label = use.profession .. (use.skill > 0 and (" " .. use.skill) or "")
        tooltip:AddLine(string.format("  %s: %s x%d%s", label, use.name, use.qty, isKnown and " (known)" or ""), r, g, b)
    end
    if #uses > limit then
        tooltip:AddLine(string.format("  +%d more%s", #uses - limit, IsShiftKeyDown() and "" or " (hold Shift)"), 0.6, 0.6, 0.6)
    end
end

function Tooltip.Install()
    if Tooltip.installed then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            -- Never let a pricing hiccup break the game's tooltip.
            pcall(addLines, tooltip, data)
            pcall(addSalesLines, tooltip, data)
            pcall(addUsedInLines, tooltip, data)
        end)
        Tooltip.installed = true
    end
end
