-- Copper -> "1g 23s 45c" with coin icons. Adapted from Disenchantry's Prices.FormatMoney (MIT, see NOTICE).
local _, ns = ...
local Money = {}
ns.Money = Money

local UNITS = {
    {10000, "g", "Interface\\MoneyFrame\\UI-GoldIcon"},
    {100, "s", "Interface\\MoneyFrame\\UI-SilverIcon"},
    {1, "c", "Interface\\MoneyFrame\\UI-CopperIcon"},
}

function Money.Format(copper)
    if not ns.IsNumber(copper) or copper <= 0 then return "" end
    copper = math.floor(copper)
    local parts = {}
    for _, unit in ipairs(UNITS) do
        local amount = math.floor(copper / unit[1])
        copper = copper - amount * unit[1]
        if amount > 0 then
            parts[#parts + 1] = amount .. unit[2] .. "|T" .. unit[3] .. ":0|t"
        end
    end
    return table.concat(parts, " ")
end

-- Signed variant for profits: "-1s 20c" when negative.
function Money.FormatSigned(copper)
    if not ns.IsNumber(copper) then return "" end
    if copper < 0 then return "-" .. Money.Format(-copper) end
    return Money.Format(copper)
end

-- "1g 20s 5c", "1g20s", "35s", "1.5g" or plain copper ("120") -> copper, or nil.
function Money.Parse(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub("|t.-|t", ""):gsub("%s+", "")
    if text == "" then return nil end
    if text:match("^%d+$") then return tonumber(text) end
    local total, rest = 0, text
    for amount, unit in text:gmatch("(%d+%.?%d*)([gsc])") do
        total = total + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    rest = rest:gsub("%d+%.?%d*[gsc]", "")
    if rest ~= "" or total <= 0 then return nil end
    return math.floor(total + 0.5)
end
