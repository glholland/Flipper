"""Offline preview of Flipper's Recipes tab using a decoded Auctionator price CSV.

Usage: python tools/preview_recipes.py [prices.csv] [Profession ...]
Same rules as the addon: profit = avg output * AH price * 0.95 - reagent AH prices.
"""
import csv
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSV = pathlib.Path(r"C:\Users\igots\Documents\wow-tools\auction-data\forever_ah_prices_latest.csv")
CUT = 0.05

args = sys.argv[1:]
csv_path = pathlib.Path(args.pop(0)) if args and args[0].endswith(".csv") else CSV
professions = set(args) or {"Tailoring", "Cooking", "Enchanting", "First Aid"}

prices, names = {}, {}
with open(csv_path, newline="", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        price = int(row["latest_min_copper"] or 0)
        if price > 0:
            prices[int(row["item_id"])] = price
            names[int(row["item_id"])] = row["name"]

entry = re.compile(r'\[(\d+)\] = \{"([^"]+)", (\d+), ("(?:[^"\\]|\\.)*"), (\d+), (\d+), (\d+), \{([^}]*)\}\}')
rows = []
for m in entry.finditer((ROOT / "Flipper" / "Data" / "RecipeDB.lua").read_text(encoding="utf-8")):
    item, prof, skill, name, out, qmin, qmax, flat = m.groups()
    item, out = int(item), int(out)
    if prof not in professions or item not in prices or out not in prices:
        continue
    nums = [int(x) for x in flat.split(",")]
    reagents = list(zip(nums[::2], nums[1::2]))
    if any(r not in prices for r, _ in reagents):
        continue
    value = math.floor(prices[out] * (1 - CUT)) * (int(qmin) + int(qmax)) / 2
    cost = sum(prices[r] * q for r, q in reagents)
    profit = value - cost
    if profit > 0:
        rows.append((profit, names[item], prof, int(skill), prices[item], math.ceil(prices[item] / profit)))

def g(c):
    return f"{int(c) // 10000}g {int(c) % 10000 // 100:02d}s {int(c) % 100:02d}c"

print(f"{'Recipe':42} {'Prof':10} {'Skill':>5} {'AH price':>13} {'Profit/craft':>13} {'Payback':>8}")
for profit, name, prof, skill, price, payback in sorted(rows, reverse=True)[:25]:
    print(f"{name[:42]:42} {prof:10} {skill:5} {g(price):>13} {g(profit):>13} {payback:>8}")
print(f"{len(rows)} profitable recipe items with full price data")
