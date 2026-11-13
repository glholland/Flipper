-- Remembers the recipes this character knows, read from the open profession window.
-- On Forever the recipe ID is the craft's spell ID; GetFilteredRecipeIDs lists what the
-- window shows (ReagentScout's in-game scan confirmed this API works on the client).
local _, ns = ...
local Recipes = {}
ns.Recipes = Recipes

local byReagent

local function store() return FlipperCharDB and FlipperCharDB.recipes end

local function schematicToRecipe(info, schematic, profession)
    if not schematic or not ns.IsNumber(schematic.outputItemID) or schematic.outputItemID <= 0 then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        -- Only required, item-based slots; optional/finishing reagents don't change the base craft.
        if first and first.itemID and slot.required ~= false and ns.IsNumber(slot.quantityRequired) then
            reagents[#reagents + 1] = {first.itemID, slot.quantityRequired}
        end
    end
    if #reagents == 0 then return nil end
    return {
        name = info.name or schematic.name,
        profession = profession,
        output = schematic.outputItemID,
        qtyMin = schematic.quantityMin or 1,
        qtyMax = schematic.quantityMax or schematic.quantityMin or 1,
        reagents = reagents,
    }
end

-- Reads every learned recipe in the open profession window. Returns how many were stored.
function Recipes.Capture()
    local T, saved = C_TradeSkillUI, store()
    if not saved or not T or not T.GetFilteredRecipeIDs or not T.GetRecipeSchematic then return 0 end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local profession = base and base.professionName or "?"
    local count = 0
    for _, id in ipairs(T.GetFilteredRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then
            local ok, schematic = pcall(T.GetRecipeSchematic, id, false)
            local recipe = ok and schematicToRecipe(info, schematic, profession)
            if recipe then saved[id] = recipe; count = count + 1 end
        end
    end
    byReagent = nil
    return count
end

-- Recipes that consume `itemID`.
function Recipes.UsingReagent(itemID)
    local saved = store()
    if not saved then return {} end
    if not byReagent then
        byReagent = {}
        for id, recipe in pairs(saved) do
            for _, reagent in ipairs(recipe.reagents) do
                local list = byReagent[reagent[1]] or {}
                list[#list + 1] = recipe
                byReagent[reagent[1]] = list
                recipe.id = id
            end
        end
    end
    return byReagent[itemID] or {}
end

function Recipes.All()
    return pairs(store() or {})
end

-- Craft options for one unit of an item, for Logic.BestUse.
function Recipes.CraftOptions(itemID)
    local options = {}
    for _, recipe in ipairs(Recipes.UsingReagent(itemID)) do
        local perUnit = ns.Logic.ReagentValue(recipe, itemID, ns.Prices.AH, ns.AH_CUT)
        if perUnit then options[#options + 1] = {name = recipe.name, perUnit = perUnit} end
    end
    return options
end
