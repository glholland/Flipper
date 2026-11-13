-- Recipes for sale on the AH that you don't know yet and that would make money.
-- Unlearned recipes can't be read from the client, so the recipe data ships in Data/RecipeDB.lua
-- (generated from Blizzard's Forever game data). Prices come from Auctionator/TSM.
local _, ns = ...
local Shop = {}
ns.RecipeShop = Shop

local EVERYTHING = "*"
local CRAFTING = {"Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid",
    "Leatherworking", "Tailoring"}

-- Which recipes the tab shows: nil = your professions, "*" = every profession, or one profession.
function Shop.Filter() return FlipperDB and FlipperDB.recipeFilter end

function Shop.FilterLabel()
    local filter = Shop.Filter()
    if filter == nil then return "All mine" end
    if filter == EVERYTHING then return "Every profession" end
    return filter
end

-- Cycles: your professions -> each of your crafting professions -> every profession -> ...
function Shop.NextFilter()
    local choices = {false}
    local yours = Shop.Professions()
    for _, name in ipairs(CRAFTING) do if yours[name] then choices[#choices + 1] = name end end
    choices[#choices + 1] = EVERYTHING
    local current = Shop.Filter() or false
    local nextIndex = 1
    for i, choice in ipairs(choices) do if choice == current then nextIndex = i % #choices + 1 end end
    FlipperDB.recipeFilter = choices[nextIndex] or nil
end

function Shop.SetEverything() FlipperDB.recipeFilter = EVERYTHING end

-- Your professions and skill: GetProfessions works without any window open;
-- Recipes.Capture also records skill when a profession window opens.
function Shop.Professions()
    local saved = FlipperCharDB and FlipperCharDB.professions or {}
    if GetProfessions and GetProfessionInfo then
        for _, index in ipairs({GetProfessions()}) do
            if index then
                local name, _, skill = GetProfessionInfo(index)
                if name and ns.IsNumber(skill) then saved[(name:gsub("^Classic ", ""))] = skill end
            end
        end
    end
    if FlipperCharDB then FlipperCharDB.professions = saved end
    return saved
end

local function knownNames()
    local names, scanned = {}, {}
    for _, recipe in ns.Recipes.All() do
        if recipe.name then names[recipe.name:lower()] = true end
        if recipe.profession then scanned[recipe.profession] = true end
    end
    return names, scanned
end

-- {{itemID, name, icon, quality, price, profit, payback, profession, skill, status}} sorted by profit.
-- status: "learnable" (your profession, skill high enough), "skill" (need more skill),
-- "other" (not your profession; only with showAll), "unverified" (profession window never opened).
function Shop.Rows()
    local professions = Shop.Professions()
    local known, scanned = knownNames()
    local filter = Shop.Filter()
    local rows = {}
    for itemID, entry in pairs(ns.RecipeDB or {}) do
        local recipe = ns.Logic.RecipeFromDB(entry)
        local yourSkill = professions[recipe.profession]
        local shown = filter == EVERYTHING or (filter == nil and yourSkill) or recipe.profession == filter
        if shown and not known[recipe.name:lower()] then
            local price = ns.Prices.AH(itemID)
            if price then
                local margin = ns.Logic.CraftMargin(recipe, ns.Prices.AH, ns.AH_CUT, ns.Prices.Fair)
                -- The recipe item's own name ("Pattern: ...") is needed to buy it; rows wait
                -- until its info loads (GET_ITEM_INFO_RECEIVED refreshes the window).
                local name, _, quality, icon  -- local _: assigning the global one taints Blizzard code
                if margin.profit and margin.profit > 0 then
                    name, _, quality, icon = ns.Compat.ItemInfo(itemID)
                end
                if name then
                    local status = not yourSkill and "other"
                        or (yourSkill < recipe.skill and "skill")
                        or (not scanned[recipe.profession] and "unverified")
                        or "learnable"
                    local vendorPrice = ns.Vendors.BuyPrice(itemID)
                    rows[#rows + 1] = {itemID = itemID, name = name, icon = icon, quality = quality,
                        vendor = vendorPrice, sellers = vendorPrice and ns.Vendors.Sellers(itemID) or nil,
                        price = price, profit = margin.profit, payback = ns.Logic.Payback(price, margin.profit),
                        profession = recipe.profession, skill = recipe.skill, status = status}
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.name < b.name
    end)
    return rows
end

-- Compares recipes read from the client with the shipped data. Prints mismatches.
function Shop.Verify()
    local db = {}
    for _, entry in pairs(ns.RecipeDB or {}) do
        local recipe = ns.Logic.RecipeFromDB(entry)
        db[recipe.profession .. ":" .. recipe.name:lower()] = recipe
    end
    local checked, mismatched = 0, 0
    for _, live in ns.Recipes.All() do
        local shipped = live.name and db[(live.profession or "?") .. ":" .. live.name:lower()]
        if shipped then
            checked = checked + 1
            local same = shipped.output == live.output and #shipped.reagents == #live.reagents
            if same then
                local want = {}
                for _, r in ipairs(shipped.reagents) do want[r[1]] = r[2] end
                for _, r in ipairs(live.reagents) do if want[r[1]] ~= r[2] then same = false end end
            end
            if not same then
                mismatched = mismatched + 1
                ns.Print("differs from game: " .. live.name)
            end
        end
    end
    ns.Print(string.format("recipe data %s: %d of your recipes checked, %d differ.",
        ns.RecipeDBBuild or "?", checked, mismatched))
end
