# Development

## Layout

```
Flipper/
  Flipper.toc        load order
  Flipper.lua        events, ticking, slash commands
  Core/
    Init.lua         namespace, defaults, day numbers
    Logic.lua        pure pricing and sales rules (tested offline)
    Money.lua        copper formatting (tested offline)
    Compat.lua       client API wrappers
    Prices.lua       AH, average, fair and vendor prices
    Recipes.lua      recipes read from profession windows
    Bags.lua         best use per bag item, hand-off to Auctionator's Selling tab
    Scanner.lua      browse scan for the Sell to vendor tab
    Market.lua       full scans and sales stats
    History.lua      price and sales history rows
    Deals.lua        underpriced items
    Vendors.lua      vendor memory, Questie lookups, vendor flips
    RecipeShop.lua   unlearned recipes worth buying
  UI/
    Window.lua       the window, AH tab and all list views
    Tooltip.lua      tooltip verdict and "used in" lines
  Data/              generated, see docs/data.md
tests/               Lua tests and their Python runner
tools/               data generators, TOC check, packaging
```

Rules that keep `Logic.lua` testable: no client calls, prices come in through function arguments.

## The Forever client

Forever runs Blizzard's Mainline UI on the 12.1.5 API (interface 16001).

- The old globals are gone: use `C_Item`, `C_Container`, `C_TradeSkillUI`, `C_AuctionHouse`, `C_MerchantFrame`.
- Numbers from the API can be secret values. `ns.IsNumber` rejects them.
- Time-left bands from `GetReplicateItemTimeLeft` run 1 to 4, not 0 to 3.
- The client does not return seller names for other players' auctions.
- Blizzard's UI source for this client is the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).

## Ground rules

- **Never buy or post.** No purchase or posting API calls; hand over to Auctionator.
- **Never leak a global.** A stray global taints Blizzard's UI and breaks action bars in combat. `luacheck` fails the build on one. Note that `_` is a global unless declared `local`.
- **Don't modify Blizzard frames.** The AH tab goes through LibAHTab.
- **Big lists must not request item data.** Build rows with `ItemInfo(id, true)` and let visible rows load their own names.
- **Licensing.** Flipper adapts MIT code from Disenchantry (see `NOTICE`). GPL addons such as ReagentScout and Auctioneer are reference only; do not copy code or data from them.

## Tests

```bash
pip install lupa
python tests/run_tests.py --syntax
```

This runs, under Lua 5.1:

- `tests/test_logic.lua`: the pure pricing, sales and disenchant rules.
- `tests/test_scans.lua`: scenarios that drive the real `Scanner` and `Market` code against `tests/fake_wow.lua`, a stand-in for the client's auction house API, clock and timers, and Auctionator's scan frames. Covered: full scans with and without Auctionator, shared cooldowns, scans Auctionator starts itself, adopting its summary scan, batched reading, the AH closing or not answering, sales counted between two scans, and when auto quick scan runs.
- With `--syntax`, every file in the TOC is compiled.

The fake is only as accurate as our understanding of the API: when the real client behaves differently, fix `fake_wow.lua` along with the code. UI code is not covered; check it in game.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

| Job | Checks |
|---|---|
| Lint | `luac5.1 -p` on every Lua file, then `luacheck` (`.luacheckrc`) |
| Tests | `python tests/run_tests.py --syntax` |
| TOC and tools | `python tools/check_toc.py`; Python tools compile |
| Package | `python tools/package.py`; uploads a dev zip (kept 14 days) |

## Releases

Tag a commit and push the tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The Release workflow reruns CI, builds `Flipper-0.2.0.zip` with that version written into the TOC, and publishes a GitHub release with generated notes. A tag containing a hyphen (`v0.3.0-beta1`) is published as a pre-release.

To work on the addon locally, link the `Flipper` folder into `_forever_/Interface/AddOns` instead of copying it.
