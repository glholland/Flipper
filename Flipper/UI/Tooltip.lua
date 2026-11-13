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
