-- Client wrappers. Forever runs the Mainline UI on the 12.1.5 API, where the old item
-- globals (GetItemInfo, GetItemIcon, ...) are gone; everything goes through C_Item.
-- Pattern adapted from Disenchantry's Core/Client.lua (MIT, see NOTICE).
local _, ns = ...
local Compat = {}
ns.Compat = Compat

local function call(modern, legacy, ...)
    local api = modern or legacy
    if api then return api(...) end
end

local requested = {}

-- name, link, quality, icon, sellPrice, classID, stackCount; nil while uncached
-- (a load is requested and GET_ITEM_INFO_RECEIVED fires when it arrives).
-- `noRequest`: only return what's cached; don't ask the server (for big lists, where only
-- the rows on screen should trigger loads).
function Compat.ItemInfo(item, noRequest)
    local name, link, quality, _, _, _, _, stack, _, icon, sellPrice, classID =
        call(C_Item and C_Item.GetItemInfo, GetItemInfo, item)
    if not name then
        if not noRequest and type(item) == "number" and not requested[item] and C_Item and C_Item.RequestLoadItemDataByID then
            requested[item] = true
            C_Item.RequestLoadItemDataByID(item)
        end
        return nil
    end
    return name, link, quality, icon, sellPrice, classID, stack
end

function Compat.ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function Compat.ContainerSlots(bag)
    return call(C_Container and C_Container.GetContainerNumSlots, GetContainerNumSlots, bag) or 0
end

-- itemID, count for one bag slot, or nil.
function Compat.ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then return info.itemID, info.stackCount or 1 end
        return nil
    end
end

function Compat.AuctionHouseOpen()
    return AuctionHouseFrame and AuctionHouseFrame:IsShown() or false
end
