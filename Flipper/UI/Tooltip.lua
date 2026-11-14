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

-- "Tailoring 125: Silk Bag x3" for every recipe Flipper knows of that takes this item.
-- Your own professions come first; green means you have the skill for it.
local USED_IN_SHOWN, USED_IN_SHIFT = 5, 20
local usedIn
local function recipesUsing(itemID)
    if not usedIn then
        usedIn = {}
        for _, entry in pairs(ns.RecipeDB or {}) do
            local flat = entry[7] or {}
            for i = 1, #flat - 1, 2 do
                local list = usedIn[flat[i]] or {}
                usedIn[flat[i]] = list
                list[#list + 1] = {profession = entry[1], skill = entry[2] or 0, name = entry[3], qty = flat[i + 1]}
            end
        end
    end
    -- The shipped data only has recipes taught by an item (patterns, plans...). Recipes you
    -- learned from a trainer come from your own profession windows.
    local uses, have = {}, {}
    for _, use in ipairs(usedIn[itemID] or {}) do uses[#uses + 1] = use; have[use.name:lower()] = true end
    for _, recipe in ipairs(ns.Recipes.UsingReagent(itemID)) do
        if recipe.name and not have[recipe.name:lower()] then
            have[recipe.name:lower()] = true
            local qty = 0
            for _, reagent in ipairs(recipe.reagents) do if reagent[1] == itemID then qty = qty + reagent[2] end end
            uses[#uses + 1] = {profession = recipe.profession or "?", skill = 0, name = recipe.name, qty = qty, known = true}
        end
    end
    return #uses > 0 and uses or nil
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
    local limit = IsShiftKeyDown() and USED_IN_SHIFT or USED_IN_SHOWN
    tooltip:AddLine("|cff4ade80Flipper|r Used in " .. #uses .. (#uses == 1 and " recipe" or " recipes"), 1, 1, 1)
    for i = 1, math.min(#uses, limit) do
        local use = uses[i]
        local skill = mine[use.profession]
        local r, g, b = 0.6, 0.6, 0.6
        if skill and skill >= use.skill then r, g, b = 0.29, 0.87, 0.5 elseif skill then r, g, b = 0.97, 0.44, 0.44 end
        local level = use.known and "(known)" or tostring(use.skill)
        tooltip:AddLine(string.format("  %s %s: %s x%d", use.profession, level, use.name, use.qty), r, g, b)
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
