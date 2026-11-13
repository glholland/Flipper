# Flipper

A World of Warcraft: Forever addon that points at easy money:

- **Flips:** auction house listings cheaper than what a vendor pays for them. Buy, then sell to any vendor.
- **Bags:** the best use of every item you carry: vendor it, auction it, or craft it into something worth more (e.g. sell fish raw vs. cook them).
- **Crafts:** profit per craft for every recipe your character knows, at current AH prices.
- **Vendor:** things vendors sell that go for 20%+ more on the AH, with where to buy them. Click a row for a map pin to the vendor. Every merchant you open is remembered (exact prices, limited stock, location); with Questie installed, its database adds vendors you haven't visited.
- **Recipes:** unlearned recipes on the AH that would make money, with the vendor price or "Drop".
- **Tooltips:** AH value after the 5% cut, vendor price and the best use, on every item.

- **Sales estimates:** the AH never says whether someone else's auction sold, so the **Full scan** button (Flips tab, `/flip market`) records every auction and compares it with your previous full scan: listings that ran out of time count as expired, ones the same seller relisted elsewhere as cancelled, the rest as sold. That fills the **Sold/day** columns and a "Market: ~x sold/day, y% of listings sell" tooltip line over a few days of AH visits (one full scan per 15 minutes). A seller who cancels without relisting is counted as a sale, so treat it as an estimate. Your own exact sold/failed counts come from Journalator.

Sale values use a *fair price*: the cheapest listing, unless it's more than twice Auctionator's 21-day average (one wishful seller), in which case the average.

Prices come from Auctionator (or TSM if installed). Flipper never buys anything itself: clicking a flip opens Auctionator's shopping search, and you buy with its buttons.

## Getting Started

1. The addon folder `Flipper/` is linked into `_forever_\Interface\AddOns\Flipper`. Restart the game fully the first time (a `/reload` doesn't pick up new addon folders).
2. Scan the AH once with Auctionator so Flipper has prices.
3. Open each profession window once (Tailoring, Enchanting, Cooking...) so Flipper learns your recipes.
4. Commands:
   - `/flip` toggles the window
   - `/flip scan` opens the Flips tab and scans (auction house must be open)
   - `/flip bags`, `/flip crafts` open those tabs
   - `/flip minprofit 50` ignores flips under 50 copper per item (default 10)
   - `/flip tooltip` turns tooltip lines on/off

## Development

Pure pricing logic lives in `Flipper/Core/Logic.lua` and `Core/Money.lua` and is tested offline under Lua 5.1:

```bash
pip install lupa
python tests/run_tests.py --syntax
```

Forever runs Blizzard's Mainline UI on the 12.1.5 API: use `C_Item`, `C_Container`, `C_TradeSkillUI`, `C_AuctionHouse`; the old item globals (`GetItemInfo`, `GetItemSpell`...) are gone. Blizzard's UI source for the client is the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).

Plan: `docs/superpowers/plans/2026-11-13-flipper.md`. Third-party notices: `NOTICE`.
