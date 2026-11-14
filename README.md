# Flipper

A World of Warcraft: Forever addon that shows where the gold is: underpriced auctions, vendor flips, what to do with each item in your bags, and which crafts and recipes pay.

![The Buy from vendor tab](docs/images/buy-from-vendor.png)

Flipper only reads and advises. It never buys or posts; rows hand you over to Auctionator, where you confirm the purchase or the price yourself.

## What it does

| Tab | Shows |
|---|---|
| **Deals** | Items listed at 70% or less of their usual price, with the profit from reselling at the average. |
| **Sell to vendor** | Auctions cheaper than what a vendor pays for the item. |
| **Buy from vendor** | Vendor goods that sell for 20%+ more on the AH, and where to buy them. |
| **Bags** | The best use of each item you carry: auction, vendor, or craft. |
| **Crafts** | Profit per craft for the recipes you know. |
| **Recipes** | Recipes for sale that you don't know and that would pay for themselves. |
| **History** | Price history for every item, plus estimated sales from full scans. |

Item tooltips get a one-line verdict (keep, craft, auction or vendor) and the recipes your professions use the item in.

## Requirements

- World of Warcraft: Forever.
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) for prices and the AH tab. TSM prices are used instead if TSM is installed.
- Optional: **Questie** (vendor locations for items you haven't seen at a vendor) and **Journalator** (your own sold/unsold counts in the tooltip).

## Install

1. Download `Flipper-<version>.zip` from [Releases](https://github.com/glholland/Flipper/releases).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns`, so that `AddOns/Flipper/Flipper.toc` exists.
3. Restart the game. A `/reload` does not pick up a new addon.

Full instructions, updating, and installing from source: [Install guide](docs/install.md).

## First steps

1. Open the auction house and run an Auctionator scan, so there are prices to work with.
2. Open each of your profession windows once. Flipper reads your recipes from them.
3. Click the **Flipper** tab at the bottom of the auction house, or type `/flip` anywhere.
4. Press **Full** on the Sell to vendor tab on most AH visits. Two full scans between 15 minutes and 12 hours apart start filling the Sold/day columns.

## Documentation

- [Install guide](docs/install.md): finding the AddOns folder, updating, installing from source.
- [User guide](docs/guide.md): every tab, the tooltip and the slash commands.
- [Sales estimates](docs/sales-estimates.md): how Sold/day is worked out and how far to trust it.
- [Data](docs/data.md): where prices, recipes and vendor information come from.
- [Troubleshooting](docs/troubleshooting.md)
- [Development](docs/development.md): layout, tests, CI and releases.

Third-party notices are in [NOTICE](NOTICE).
