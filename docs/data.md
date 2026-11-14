# Data

## Live sources

| Source | Used for |
|---|---|
| Auctionator (or TSM) | Current and average AH prices, price history |
| The game client | Your bags, your recipes, vendor sell prices, the vendors you open |
| Full scans | Snapshots for the [sales estimates](sales-estimates.md) |
| Questie (optional) | Which NPCs sell an item and where they stand |
| Journalator (optional) | Your own sold and unsold counts |

## Shipped data

Three files in `Flipper/Data` are generated from Blizzard's Forever game data API. The client cannot read recipes you haven't learned or prices at vendors you haven't visited, so these ship with the addon.

| File | Contents | Generator |
|---|---|---|
| `RecipeDB.lua` | 1,608 recipe items (patterns, plans, formulas...) and the craft each teaches | `tools/build_recipe_db.py` |
| `CraftDB.lua` | All 2,493 profession recipes with reagents, trainer recipes and enchants included | `tools/build_craft_db.py` |
| `BuyPriceDB.lua` | 11,064 vendor purchase prices | `tools/build_price_db.py` |

Known gaps:

- Trainer-taught recipes have no skill level in Blizzard's data.
- Blizzard's data does not say where a recipe is learned. Vendor locations come from Questie at runtime.
- "Blueprint" items (campsite structures) are left out of `RecipeDB.lua`.

## Regenerating

The generators read a local cache of API responses built by the separate `wowapi` project (namespace `static-forever-us`). After refreshing that cache:

```bash
python tools/build_recipe_db.py
python tools/build_craft_db.py
python tools/build_price_db.py
```

Each takes an optional path to the cache database. `/flip verify` in game then compares the shipped recipes against the ones your character knows.

## Saved variables

- `FlipperDB` (account): settings, window layout, vendor memory, the last full-scan snapshot and 14 days of sales stats.
- `FlipperCharDB` (character): known recipes and profession skill.

`tools/export_history.py` merges Flipper's sales stats with Auctionator's price history into a CSV for analysis outside the game.
