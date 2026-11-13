-- Shared namespace, constants and saved-variable defaults. No client calls at load time.
local addonName, ns = ...
ns.name = addonName or "Flipper"
ns.CALLER_ID = "Flipper"      -- id passed to Auctionator's API
ns.AH_CUT = 0.05              -- auction house cut on sales; vendor sales have none

ns.DEFAULTS = {
    minFlipProfit = 10,       -- copper per unit; smaller flips are noise
    window = {},
    tooltip = true,
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

function ns.Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4ade80Flipper:|r " .. tostring(message)) end
end
