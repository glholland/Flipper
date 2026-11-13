-- Offline tests for Flipper's pure pricing logic. Run with: python tests/run_tests.py
local ns = ...
local Logic, Money = ns.Logic, ns.Money
local failures, passed = {}, 0

local function eq(name, got, want)
    if got == want then passed = passed + 1
    else failures[#failures + 1] = string.format("%s: got %s, want %s", name, tostring(got), tostring(want)) end
end

-- NetAH
eq("NetAH 5% cut", Logic.NetAH(100, 0.05), 95)
eq("NetAH floors", Logic.NetAH(99, 0.05), 94)
eq("NetAH nil price", Logic.NetAH(nil, 0.05), nil)

-- EvaluateFlip
eq("flip grenade", Logic.EvaluateFlip(240, 500, 1), 260)
eq("flip vendor 0", Logic.EvaluateFlip(100, 0, 1), nil)
eq("flip vendor nil (uncached)", Logic.EvaluateFlip(100, nil, 1), nil)
eq("flip no listing price", Logic.EvaluateFlip(0, 500, 1), nil)
eq("flip below min profit", Logic.EvaluateFlip(495, 500, 10), nil)
eq("flip at min profit", Logic.EvaluateFlip(490, 500, 10), 10)
eq("flip AH above vendor", Logic.EvaluateFlip(600, 500, 1), nil)

-- CraftMargin: 1-3 output averages to 2
local prices = {[10] = 1000, [20] = 100, [21] = 50}
local function price(id) return prices[id] end
local bag = {output = 10, qtyMin = 1, qtyMax = 3, reagents = {{20, 2}, {21, 1}}}
local m = Logic.CraftMargin(bag, price, 0.05)
eq("craft value avg qty", m.value, 1900)          -- 2 * floor(1000*0.95)
eq("craft cost", m.cost, 250)                      -- 2*100 + 50
eq("craft profit", m.profit, 1650)
eq("craft nothing missing", #m.missing, 0)

local unpriced = {output = 10, qtyMin = 1, qtyMax = 1, reagents = {{20, 1}, {99, 1}}}
local m2 = Logic.CraftMargin(unpriced, price, 0.05)
eq("craft missing reagent listed", m2.missing[1], 99)
eq("craft missing -> profit nil", m2.profit, nil)

local noOutputPrice = {output = 77, qtyMin = 1, qtyMax = 1, reagents = {{20, 1}}}
eq("craft unpriced output -> profit nil", Logic.CraftMargin(noOutputPrice, price, 0.05).profit, nil)

-- ReagentValue: cooking 1 raw fish (30) + 1 spice (21 @50) -> cooked fish (31 @ 400)
prices[30], prices[31] = 5, 400
local cook = {output = 31, qtyMin = 1, qtyMax = 1, reagents = {{30, 1}, {21, 1}}}
eq("reagent value raw fish", Logic.ReagentValue(cook, 30, price, 0.05), 330)   -- 380 - 50
local twoRaw = {output = 31, qtyMin = 1, qtyMax = 1, reagents = {{30, 2}}}
eq("reagent value per unit", Logic.ReagentValue(twoRaw, 30, price, 0.05), 190)
local otherUnpriced = {output = 31, qtyMin = 1, qtyMax = 1, reagents = {{30, 1}, {99, 1}}}
eq("reagent value other unpriced", Logic.ReagentValue(otherUnpriced, 30, price, 0.05), nil)

-- BestUse
local b = Logic.BestUse{ah = 145, vendor = 4, crafts = {{name = "Cook", perUnit = 120}}, cut = 0.05}
eq("best use sell raw", b.action, "ah")
eq("best use perUnit net", b.perUnit, 137)
b = Logic.BestUse{ah = 5, vendor = 4, crafts = {{name = "Cook", perUnit = 46}}, cut = 0.05}
eq("best use craft", b.action, "craft")
eq("best use craft name", b.craftName, "Cook")
b = Logic.BestUse{ah = 105, vendor = 99, crafts = {}, cut = 0.05}  -- net AH 99 ties vendor
eq("best use tie -> vendor", b.action, "vendor")
b = Logic.BestUse{ah = nil, vendor = 0, crafts = {}, cut = 0.05}
eq("best use nothing priced", b.action, "none")
b = Logic.BestUse{ah = 200, vendor = 0, crafts = {}, cut = 0.05}
eq("best use unsellable to vendor", b.action, "ah")

-- Payback / RecipeFromDB
eq("payback rounds up", Logic.Payback(1000, 300), 4)
eq("payback at least one craft", Logic.Payback(100, 500), 1)
eq("payback losing recipe", Logic.Payback(1000, -5), nil)
eq("payback unpriced", Logic.Payback(nil, 50), nil)
local r = Logic.RecipeFromDB({"Tailoring", 80, "Gray Woolen Robe", 2585, 1, 1, {2997, 4, 2321, 3, 4340, 1}})
eq("db profession", r.profession, "Tailoring")
eq("db output", r.output, 2585)
eq("db reagent count", #r.reagents, 3)
eq("db reagent pair", r.reagents[2][1] .. "x" .. r.reagents[2][2], "2321x3")

-- Money
local function plain(s) return (s:gsub("|T.-|t", "")) end
eq("money full", plain(Money.Format(12345)), "1g 23s 45c")
eq("money copper only", plain(Money.Format(7)), "7c")
eq("money skips zero parts", plain(Money.Format(10005)), "1g 5c")
eq("money zero", Money.Format(0), "")

return passed, failures
