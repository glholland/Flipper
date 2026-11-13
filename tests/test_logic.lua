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

-- FairPrice
eq("fair: one wishful listing -> average", Logic.FairPrice(500100, 6600), 6600)
eq("fair: normal listing kept", Logic.FairPrice(7000, 6600), 7000)
eq("fair: cheap listing kept", Logic.FairPrice(4000, 6600), 4000)
eq("fair: no average", Logic.FairPrice(7000, nil), 7000)
eq("fair: no listing", Logic.FairPrice(nil, 6600), 6600)
eq("fair: nothing", Logic.FairPrice(nil, nil), nil)
eq("fair: zero latest ignored", Logic.FairPrice(0, 6600), 6600)

-- VendorFlip: buy 1s at vendor, AH fair 5s -> 475 - 100
eq("vendor flip", Logic.VendorFlip(100, 500, 0.05, 10, 0.2), 375)
eq("vendor flip below min profit", Logic.VendorFlip(100, 110, 0.05, 10, 0), nil)
eq("vendor flip below margin", Logic.VendorFlip(10000, 11000, 0.05, 10, 0.2), nil)
eq("vendor flip no AH price", Logic.VendorFlip(100, nil, 0.05, 10, 0.2), nil)

-- CraftMargin with a separate sell price
local fair = function(id) return id == 10 and 800 or price(id) end
eq("craft sells at fair price", Logic.CraftMargin(bag, price, 0.05, fair).value, 1520)  -- 2 * 760

-- CompareSnapshots
local function snap(item, seller, price, q, tl) return {[item] = {[seller] = {[price] = {q = q, tl = tl}}}} end
local r1 = Logic.CompareSnapshots(snap(1, "A", 100, 5, 3), {}, 600)
eq("vanished early -> sold", r1[1].sold, 5)
local r2 = Logic.CompareSnapshots(snap(1, "A", 100, 5, 3), {}, 200000)
eq("vanished after max time -> expired", r2[1].expired, 5)
eq("expired not sold", r2[1].sold, 0)
local r3 = Logic.CompareSnapshots(snap(1, "A", 100, 5, 3), snap(1, "A", 90, 5, 3), 600)
eq("undercut repost -> cancelled", r3[1].cancelled, 5)
eq("undercut repost not sold", r3[1].sold, 0)
local r4 = Logic.CompareSnapshots(snap(1, "A", 100, 20, 3), snap(1, "A", 100, 15, 3), 600)
eq("partial buy -> sold", r4[1].sold, 5)
local r5 = Logic.CompareSnapshots(snap(1, "A", 100, 10, 3), snap(1, "A", 95, 6, 3), 600)
eq("repost of part -> cancelled part", r5[1].cancelled, 6)
eq("repost of part -> rest sold", r5[1].sold, 4)
local r6 = Logic.CompareSnapshots(snap(1, "A", 100, 5, 0), {}, 3600)
eq("short band gone after 1h -> expired", r6[1].expired, 5)
eq("new listings only -> nothing", next(Logic.CompareSnapshots({}, snap(1, "A", 100, 5, 3), 600)), nil)
local r7 = Logic.CompareSnapshots(snap(1, "A", 100, 5, 3), snap(1, "B", 90, 5, 3), 600)
eq("other seller's listing is not a relist", r7[1].sold, 5)

-- AddObservation / SalesRate: 12h observed, 6 sold, 2 expired
local stats = Logic.AddObservation({}, {[1] = {sold = 6, expired = 2, cancelled = 0}}, 43200, 100)
local perDay, through = Logic.SalesRate(stats, 1, 100, 14)
eq("sold per day", perDay, 12)
eq("sell-through", through, 0.75)
eq("unseen item sells 0/day", (Logic.SalesRate(stats, 2, 100, 14)), 0)
eq("under an hour observed -> nil", (Logic.SalesRate(Logic.AddObservation({}, {}, 600, 100), 1, 100, 14)), nil)
eq("outside window ignored", (Logic.SalesRate(stats, 1, 120, 14)), nil)

-- SortRows
local function names(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.name end return table.concat(t, ",") end
local function sample() return {{name = "b", v = 2}, {name = "a", v = nil}, {name = "c", v = 5}, {name = "d", v = 2}} end
local getV = function(r) return r.v end
eq("sort ascending, nil last", names(Logic.SortRows(sample(), getV, false)), "b,d,c,a")
eq("sort descending, nil last", names(Logic.SortRows(sample(), getV, true)), "c,b,d,a")
eq("sort strings case-insensitive", names(Logic.SortRows({{name = "Zed"}, {name = "apple"}}, function(r) return r.name end, false)), "apple,Zed")

-- Money
local function plain(s) return (s:gsub("|T.-|t", "")) end
eq("money full", plain(Money.Format(12345)), "1g 23s 45c")
eq("money copper only", plain(Money.Format(7)), "7c")
eq("money skips zero parts", plain(Money.Format(10005)), "1g 5c")
eq("money zero", Money.Format(0), "")

return passed, failures
