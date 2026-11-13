-- Entry point: saved variables, events, ticking and slash commands.
local addonName, ns = ...
local frame = CreateFrame("Frame")
local events = {}

local function refresh() if ns.Window.frame and ns.Window.frame:IsShown() then ns.Window.Refresh() end end

function events.ADDON_LOADED(name)
    if name ~= addonName then return end
    FlipperDB = ns.ApplyDefaults(FlipperDB, ns.DEFAULTS)
    FlipperCharDB = ns.ApplyDefaults(FlipperCharDB, ns.CHAR_DEFAULTS)
    ns.Recipes.Migrate()
    ns.Scanner.OnChanged = refresh
    ns.Tooltip.Install()
end

-- After every Auctionator scan: refresh the window and point out the best opportunities.
local function onPricesUpdated()
    ns.Prices.ClearCache()
    refresh()
    local best = ns.RecipeShop.Rows()[1]
    if best and best.status == "learnable" then
        ns.Print(string.format("new prices: %s on the AH makes %s per craft (/flip recipes)",
            best.name, ns.Money.Format(best.profit)))
    end
end
function events.PLAYER_LOGIN()
    ns.Scanner.InstallHooks()
    ns.RecipeShop.Professions()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.RegisterForDBUpdate then
        pcall(api.RegisterForDBUpdate, ns.CALLER_ID, onPricesUpdated)
    end
end
function events.AUCTION_HOUSE_SHOW() ns.Scanner.InstallHooks(); refresh() end
function events.AUCTION_HOUSE_CLOSED() ns.Scanner.OnEvent("AUCTION_HOUSE_CLOSED"); ns.Prices.ClearCache(); refresh() end
events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function() ns.Scanner.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
events.AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function() ns.Scanner.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED") end
events.AUCTION_HOUSE_BROWSE_FAILURE = function() ns.Scanner.OnEvent("AUCTION_HOUSE_BROWSE_FAILURE") end

local function captureRecipes()
    local count = ns.Recipes.Capture()
    if count > 0 then refresh() end
end
events.TRADE_SKILL_SHOW = captureRecipes
events.TRADE_SKILL_LIST_UPDATE = captureRecipes
events.BAG_UPDATE_DELAYED = function() if ns.Window.tab == "bags" then refresh() end end

local pendingInfoRefresh
function events.GET_ITEM_INFO_RECEIVED()
    -- Arrives in bursts; refresh once.
    if pendingInfoRefresh then return end
    pendingInfoRefresh = true
    C_Timer.After(0.5, function() pendingInfoRefresh = false; refresh() end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = events[event]
    if handler then handler(...) end
end)
for event in pairs(events) do frame:RegisterEvent(event) end

local elapsed = 0
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.1 then return end
    elapsed = 0
    ns.Scanner.Tick()
end)

local commands = {
    [""] = function() ns.Window.Toggle() end,
    flips = function() ns.Window.Toggle("flips") end,
    bags = function() ns.Window.Toggle("bags") end,
    crafts = function() ns.Window.Toggle("crafts") end,
    recipes = function() ns.Window.Toggle("recipes") end,
    verify = function() ns.RecipeShop.Verify() end,
    reset = function() ns.Window.ResetGeometry(); ns.Print("window size and position reset") end,
    scan = function() ns.Window.Toggle("flips"); ns.Scanner.Start() end,
    tooltip = function()
        FlipperDB.tooltip = not FlipperDB.tooltip
        ns.Print("tooltip lines " .. (FlipperDB.tooltip and "on" or "off"))
    end,
}
local function help()
    ns.Print("/flip - window | /flip scan | /flip bags | /flip crafts | /flip recipes [all] | /flip verify | /flip reset | /flip tooltip | /flip minprofit <copper>")
end
SLASH_FLIPPER1 = "/flip"
SLASH_FLIPPER2 = "/flipper"
SlashCmdList.FLIPPER = function(message)
    local command, arg = strtrim(message or ""):lower():match("^(%S*)%s*(.-)$")
    if command == "recipes" and arg == "all" then
        ns.RecipeShop.SetEverything()
        ns.Window.Toggle("recipes")
        return
    end
    if command == "minprofit" then
        local copper = tonumber(arg)
        if copper and copper >= 1 then
            FlipperDB.minFlipProfit = math.floor(copper)
            ns.Print("minimum flip profit " .. ns.Money.Format(FlipperDB.minFlipProfit) .. " per item")
        else help() end
        return
    end
    (commands[command] or help)()
end
