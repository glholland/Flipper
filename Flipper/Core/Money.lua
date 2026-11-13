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
