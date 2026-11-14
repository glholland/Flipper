-- Shared namespace, constants and saved-variable defaults. No client calls at load time.
local addonName, ns = ...
ns.name = addonName or "Flipper"
ns.CALLER_ID = "Flipper"      -- id passed to Auctionator's API
ns.AH_CUT = 0.05              -- auction house cut on sales; vendor sales have none

ns.DEFAULTS = {
    minFlipProfit = 10,       -- copper per unit; smaller flips are noise
    autoQuickScan = false,    -- quick scan a few seconds after the AH opens
    window = {},
    tooltip = true,
    dealRatio = 0.7,          -- Deals: listed at 70% of the usual price or less
    minimap = {minimapPos = 200},   -- LibDBIcon-style: minimapPos (degrees), hide, lock
}
ns.CHAR_DEFAULTS = {
    recipes = {},             -- [recipeSpellID] = {name, profession, output, qtyMin, qtyMax, reagents={{id,qty}}}
}

-- Copies missing keys from defaults into a saved table, recursively.
function ns.ApplyDefaults(saved, defaults)
    saved = type(saved) == "table" and saved or {}
    for key, value in pairs(defaults) do
        if saved[key] == nil then
            saved[key] = type(value) == "table" and ns.ApplyDefaults({}, value) or value
        elseif type(value) == "table" and type(saved[key]) == "table" then
            ns.ApplyDefaults(saved[key], value)
        end
    end
    return saved
end

-- True for a plain, usable number (12.x can hand out secret values).
function ns.IsNumber(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value == value and value < math.huge
end

-- Day numbers shared with Auctionator's price history: days since 1 Jan 2020, local midnight.
local DAY0
function ns.Day(t)
    DAY0 = DAY0 or time({year = 2020, month = 1, day = 1, hour = 0})
    return math.floor(((t or time()) - DAY0) / 86400)
end
function ns.DayStart(day)
    DAY0 = DAY0 or time({year = 2020, month = 1, day = 1, hour = 0})
    return DAY0 + day * 86400
end

function ns.Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4ade80Flipper:|r " .. tostring(message)) end
end
