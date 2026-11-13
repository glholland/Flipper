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

function Tooltip.Install()
    if Tooltip.installed then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            -- Never let a pricing hiccup break the game's tooltip.
            pcall(addLines, tooltip, data)
            pcall(addSalesLines, tooltip, data)
        end)
        Tooltip.installed = true
    end
end
