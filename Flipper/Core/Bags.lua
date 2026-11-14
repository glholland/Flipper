-- Best use of everything in your bags: vendor it, auction it, or craft it into something worth more.
local _, ns = ...
local Bags = {}
ns.Bags = Bags

local BAGS = {0, 1, 2, 3, 4}
if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then BAGS[#BAGS + 1] = Enum.BagIndex.ReagentBag end

-- `bound`: soulbound, so it can't be auctioned (vendoring and crafting still work).
function Bags.Advice(itemID, bound)
    return ns.Logic.BestUse{
        ah = not bound and ns.Prices.Fair(itemID) or nil,
        vendor = ns.Prices.Vendor(itemID),
        crafts = ns.Recipes.CraftOptions(itemID),
        -- Only for enchanters; the value is the materials sold on the AH.
        disenchant = ns.Disenchant.Known() and ns.Disenchant.Value(itemID) or nil,
        cut = ns.AH_CUT,
    }
end

-- {{itemID, count, name, icon, quality, advice, total}} sorted by total value, highest first.
-- Items whose info isn't loaded yet are skipped; GET_ITEM_INFO_RECEIVED triggers a refresh.
function Bags.Rows()
    local counts, bound, slots = {}, {}, {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, ns.Compat.ContainerSlots(bag) do
            local id, count, isBound = ns.Compat.ContainerItem(bag, slot)
            if id then
                counts[id] = (counts[id] or 0) + count
                if isBound then bound[id] = true elseif not slots[id] then slots[id] = {bag, slot} end
            end
        end
    end
    local rows = {}
    for id, count in pairs(counts) do
        local name, _, quality, icon = ns.Compat.ItemInfo(id)
        if name then
            local advice = Bags.Advice(id, bound[id])
            rows[#rows + 1] = {itemID = id, count = count, name = name, icon = icon, quality = quality,
                bagSlot = slots[id], advice = advice, total = advice.perUnit * count}
        end
    end
    table.sort(rows, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return rows
end

-- Opens Auctionator's Selling tab with this bag item picked, ready to post. Flipper never
-- posts: you set the price and press Post there. Goes through the same steps Auctionator
-- takes when you right-click a bag item at the AH (its Selling tab and bag cache).
function Bags.SellInAuctionator(row)
    if not row.bagSlot then ns.Print(row.name .. " is soulbound and can't be auctioned."); return end
    if not ns.Compat.AuctionHouseOpen() then ns.Print("Open the auction house to sell " .. row.name .. "."); return end
    local events = Auctionator and Auctionator.Selling and Auctionator.Selling.Events
    local toPosting = Auctionator and Auctionator.Groups and Auctionator.Groups.Utilities
        and Auctionator.Groups.Utilities.ToPostingItem
    if not (AuctionatorTabs_Selling and AuctionatorBagCacheFrame and events and toPosting and ItemLocation) then
        ns.Print("Auctionator's Selling tab isn't available; sell " .. row.name .. " from the Sell tab.")
        return
    end
    local location = ItemLocation:CreateFromBagAndSlot(row.bagSlot[1], row.bagSlot[2])
    if not location:IsValid() or not C_AuctionHouse.IsSellItemValid(location) then
        ns.Print(row.name .. " can't be auctioned.")
        return
    end
    local ok, err = pcall(function()
        AuctionatorTabs_Selling:Click()
        local link = C_Item.GetItemLink(location)
        AuctionatorBagCacheFrame:CacheLinkInfo(link, function()
            local info = toPosting(AuctionatorBagCacheFrame:GetByLinkInstant(link, true))
            info.itemLink, info.location = link, location
            info.count = C_AuctionHouse.GetAvailablePostCount(location)
            Auctionator.EventBus:RegisterSource(Bags, "FlipperBagsSell")
            Auctionator.EventBus:Fire(Bags, events.BagItemClicked, info)
        end)
    end)
    if not ok then ns.Print("couldn't open Auctionator's Selling tab: " .. tostring(err)) end
end
