-- Best use of everything in your bags: vendor it, auction it, or craft it into something worth more.
local _, ns = ...
local Bags = {}
ns.Bags = Bags

local BAGS = {0, 1, 2, 3, 4}
if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then BAGS[#BAGS + 1] = Enum.BagIndex.ReagentBag end

function Bags.Advice(itemID)
    return ns.Logic.BestUse{
        ah = ns.Prices.Fair(itemID),
        vendor = ns.Prices.Vendor(itemID),
        crafts = ns.Recipes.CraftOptions(itemID),
        cut = ns.AH_CUT,
    }
end

-- {{itemID, count, name, icon, quality, advice, total}} sorted by total value, highest first.
-- Items whose info isn't loaded yet are skipped; GET_ITEM_INFO_RECEIVED triggers a refresh.
function Bags.Rows()
    local counts = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, ns.Compat.ContainerSlots(bag) do
            local id, count = ns.Compat.ContainerItem(bag, slot)
            if id then counts[id] = (counts[id] or 0) + count end
        end
    end
    local rows = {}
    for id, count in pairs(counts) do
        local name, _, quality, icon = ns.Compat.ItemInfo(id)
        if name then
            local advice = Bags.Advice(id)
            rows[#rows + 1] = {itemID = id, count = count, name = name, icon = icon, quality = quality,
                advice = advice, total = advice.perUnit * count}
        end
    end
    table.sort(rows, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return rows
end
