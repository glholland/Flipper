-- Where to buy things from vendors, and what vendor stock sells for more on the AH.
--
-- Two sources:
--  * Vendor memory: every merchant you open is recorded (exact prices including reputation
--    discounts, limited stock, the NPC and where you stood). Account-wide, in FlipperDB.
--  * QuestieDB (if installed): which NPCs sell an item and where they stand. Read at runtime
--    through LibQuestieDB's public API; nothing is copied from it. Buy prices for items you
--    haven't seen at a vendor come from Data/BuyPriceDB.lua (Blizzard's Forever item data).
local _, ns = ...
local Vendors = {}
ns.Vendors = Vendors

local MIN_MARGIN = 0.2           -- vendor flips must clear 20% of the vendor price after the AH cut
local MAX_SELLERS = 3

local function memory()
    if not FlipperDB then return {items = {}, npcs = {}} end
    FlipperDB.vendorItems = FlipperDB.vendorItems or {}
    FlipperDB.vendorNPCs = FlipperDB.vendorNPCs or {}
    return {items = FlipperDB.vendorItems, npcs = FlipperDB.vendorNPCs}
end

------------------------------------------------------------------------
-- Vendor memory
------------------------------------------------------------------------

local function npcIDFromGUID(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

local function playerLocation()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y = pos and pos:GetXY()
    local info = C_Map.GetMapInfo(mapID)
    return mapID, x and math.floor(x * 1000) / 10, y and math.floor(y * 1000) / 10, info and info.name
end

-- Called on MERCHANT_SHOW / MERCHANT_UPDATE: remember everything this vendor sells for gold.
function Vendors.RecordMerchant()
    if not GetMerchantNumItems or not GetMerchantItemID then return end
    local mem = memory()
    local npcID = npcIDFromGUID(UnitGUID("npc"))
    if not npcID then return end
    local mapID, x, y, zone = playerLocation()
    mem.npcs[npcID] = {name = UnitName("npc"), mapID = mapID, x = x, y = y, zone = zone, seen = time()}
    for index = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(index)
        local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
        if itemID and info and ns.IsNumber(info.price) and info.price > 0 and not info.hasExtendedCost then
            local entry = mem.items[itemID] or {sellers = {}}
            entry.price = info.price
            entry.qty = (ns.IsNumber(info.stackCount) and info.stackCount > 0) and info.stackCount or 1
            entry.limited = ns.IsNumber(info.numAvailable) and info.numAvailable >= 0 or nil
            entry.sellers[npcID] = true
            mem.items[itemID] = entry
        end
    end
    Vendors.Invalidate()
end

------------------------------------------------------------------------
-- QuestieDB (optional)
------------------------------------------------------------------------

local function questieDB()
    local db = LibQuestieDB
    if type(db) ~= "table" or not db.Item or not db.Npc then return nil end
    if db.RequireContract and not db.RequireContract(1) then return nil end
    return db
end

local function playerFactionLetter()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

local zoneDB
local function uiMapForArea(areaID)
    if zoneDB == nil then
        zoneDB = false
        if QuestieLoader and QuestieLoader.ImportModule then
            local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
            if ok and module and module.GetUiMapIdByAreaId then zoneDB = module end
        end
    end
    if zoneDB then
        local ok, uiMap = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaID)
        if ok and uiMap then return uiMap end
    end
end

local function zoneName(mapID, areaID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if info and info.name then return info.name end
    if areaID and C_Map and C_Map.GetAreaInfo then return C_Map.GetAreaInfo(areaID) end
end

-- NPC IDs Questie says sell this item, friendly to your faction.
local function questieVendors(itemID)
    local db = questieDB()
    if not db then return {} end
    local ok, npcs = pcall(db.Item.Get, itemID, "vendors")
    if not ok or type(npcs) ~= "table" then return {} end
    local mine, result = playerFactionLetter(), {}
    for _, npcID in ipairs(npcs) do
        local okF, friendly = pcall(db.Npc.Get, npcID, "friendlyToFaction")
        friendly = okF and friendly or nil
        if not mine or not friendly or friendly == "AH" or friendly == mine then result[#result + 1] = npcID end
    end
    return result
end

local function questieSeller(npcID)
    local db = questieDB()
    if not db then return nil end
    local okN, name = pcall(db.Npc.Get, npcID, "name")
    local okS, spawns = pcall(db.Npc.Get, npcID, "spawns")
    if not okN or not name then return nil end
    local seller = {name = name, source = "questie"}
    if okS and type(spawns) == "table" then
        for areaID, points in pairs(spawns) do
            local point = type(points) == "table" and points[1]
            if point and point[1] and point[1] >= 0 then
                seller.mapID = uiMapForArea(areaID)
                seller.x, seller.y = point[1], point[2]
                seller.zone = zoneName(seller.mapID, areaID)
                break
            end
        end
    end
    return seller
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------

-- Price for one unit from a vendor and whether stock is limited, or nil if no vendor sells it.
-- source: "seen" (you opened that vendor: exact) or "data" (Blizzard item data).
function Vendors.BuyPrice(itemID)
    local seen = memory().items[itemID]
    if seen and seen.price then return seen.price / (seen.qty or 1), "seen", seen.limited end
    if #questieVendors(itemID) == 0 then return nil end
    local data = ns.BuyPriceDB and ns.BuyPriceDB[itemID]
    if type(data) == "table" then return data[1] / (data[2] or 1), "data" end
    if ns.IsNumber(data) then return data, "data" end
end

function Vendors.IsVendorItem(itemID)
    return memory().items[itemID] ~= nil or #questieVendors(itemID) > 0
end

-- Up to MAX_SELLERS vendors: {name, zone, x, y, mapID, source}. Vendors you visited come first.
function Vendors.Sellers(itemID)
    local mem, sellers, seenIDs = memory(), {}, {}
    local entry = mem.items[itemID]
    if entry then
        for npcID in pairs(entry.sellers or {}) do
            local npc = mem.npcs[npcID]
            if npc and #sellers < MAX_SELLERS then
                seenIDs[npcID] = true
                sellers[#sellers + 1] = {name = npc.name, zone = npc.zone, x = npc.x, y = npc.y,
                    mapID = npc.mapID, source = "seen"}
            end
        end
    end
    for _, npcID in ipairs(questieVendors(itemID)) do
        if #sellers >= MAX_SELLERS then break end
        if not seenIDs[npcID] then
            local seller = questieSeller(npcID)
            if seller then sellers[#sellers + 1] = seller end
        end
    end
    return sellers
end

function Vendors.Describe(seller)
    if not seller then return "" end
    local text = seller.name or "?"
    if seller.zone then text = text .. ", " .. seller.zone end
    if seller.x and seller.y then text = text .. string.format(" (%.0f, %.0f)", seller.x, seller.y) end
    return text
end

-- Puts a map pin and the tracking arrow on a seller.
function Vendors.Waypoint(seller)
    if not seller or not seller.mapID or not seller.x then
        ns.Print("no map position for " .. Vendors.Describe(seller))
        return
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(seller.mapID, seller.x / 100, seller.y / 100))
        if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end
    ns.Print("waypoint: " .. Vendors.Describe(seller))
end

-- Every item a vendor is known to sell: your memory plus QuestieDB. Built once, then cached.
local function candidates()
    if Vendors.candidates then return Vendors.candidates end
    local list, seen = {}, {}
    for itemID in pairs(memory().items) do seen[itemID] = true; list[#list + 1] = itemID end
    local db = questieDB()
    if db and db.Item.GetAllIds then
        local ok, ids = pcall(db.Item.GetAllIds)
        for _, itemID in ipairs(ok and ids or {}) do
            if not seen[itemID] then
                local okV, npcs = pcall(db.Item.Get, itemID, "vendors")
                if okV and type(npcs) == "table" and #npcs > 0 then seen[itemID] = true; list[#list + 1] = itemID end
            end
        end
    end
    Vendors.candidates = list
    return list
end

-- Vendor items that sell on the AH for clearly more than the vendor charges.
-- {{itemID, name, icon, quality, buy, source, limited, fair, profit, sellers}}
-- Cached for ROWS_SECONDS: thousands of items are checked. Invalidate() after new prices.
local ROWS_SECONDS = 30
local cachedRows, cachedAt = nil, 0

function Vendors.Invalidate() cachedRows, Vendors.candidates = nil, nil end

function Vendors.FlipRows()
    if cachedRows and GetTime() - cachedAt < ROWS_SECONDS then return cachedRows end
    local minProfit = FlipperDB and FlipperDB.minFlipProfit or ns.DEFAULTS.minFlipProfit
    local rows, missingInfo = {}, false
    for _, itemID in ipairs(candidates()) do
        local fair = ns.Prices.Fair(itemID)
        if fair then
            local buy, source, limited = Vendors.BuyPrice(itemID)
            local profit = ns.Logic.VendorFlip(buy, fair, ns.AH_CUT, minProfit, MIN_MARGIN)
            if profit then
                local name, _, quality, icon = ns.Compat.ItemInfo(itemID)
                if name then
                    local sellers = Vendors.Sellers(itemID)
                    rows[#rows + 1] = {itemID = itemID, name = name, icon = icon, quality = quality, buy = buy,
                        source = source, limited = limited, fair = fair, profit = profit, sellers = sellers,
                        where = sellers[1] and Vendors.Describe(sellers[1]) or "?"}
                else
                    missingInfo = true
                end
            end
        end
    end
    -- A list with items still loading is kept briefly, then rebuilt once their info is in.
    -- Never rebuild on every arriving item: that's thousands of rebuilds.
    cachedRows = rows
    cachedAt = missingInfo and (GetTime() - ROWS_SECONDS + 5) or GetTime()
    return rows
end
