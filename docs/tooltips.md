# Tooltips

Flipper adds a short block to every item tooltip: in your bags, on the AH, in loot windows, in chat links. It answers one question: **what should I do with this item?**

Install [Auctionator](install.md#install-these-first) first. Without prices, Flipper can still list recipes, but it can't tell you whether to sell, craft or vendor.

## What a tooltip looks like

Hovering **Linen Cloth** on a tailor:

```
Flipper Keep for Tailoring (1 known, 4 recipes)  -  or auction
  Tailoring: Bolt of Linen Cloth x2 (known)  -> 23 recipes
      Tailoring 50: Linen Bag (3)
      Tailoring 70: Reinforced Linen Cape (2)
  Tailoring 45: Linen Belt x1
  +1 more use (hover with Shift held)
```

Line by line:

1. **The verdict**, after the green "Flipper".
2. **Your recipes** that use the item, at most three, the ones you know first.
3. **The next step**, indented, when a recipe turns the item into something other recipes use: here, cloth becomes bolts, and bolts go into 23 recipes.
4. **"+N more"** when some uses are hidden.

Items with nothing to say (no price, no use in your professions) get no Flipper lines at all.

## The verdict

| Verdict | Means |
|---|---|
| **Keep for Tailoring (1 known, 4 recipes)** | Your professions use it. "1 known" is recipes you've learned; the rest you could learn. "- or auction" says what to do if you don't need it. |
| **Craft Silk Bag: 3s each** | A recipe you know turns it into something worth more than selling it, after reagent costs and the AH cut. |
| **Disenchant it: ~11s in materials** | Enchanters only. The materials are worth more on the AH than the item. |
| **Auction it** | Worth more on the AH (after the 5% cut) than at a vendor, and you don't craft with it. |
| **Vendor it** | A vendor pays more than the AH would, or it doesn't sell on the AH. |
| **No use for your professions** | Shown only with Shift held, when other professions use it. |

With Auctionator loaded, the verdict leaves out the vendor and auction prices, because Auctionator already shows them in the same tooltip.

"Craft" only considers recipes you know. "Keep" counts any recipe in your professions, known or not, and doesn't judge whether the craft is profitable.

## Recipe lines

```
  Tailoring 70: Reinforced Linen Cape x2 (known)
  |         |   |                      |   |
  |         |   recipe                 |   you know it
  |         skill needed               how many of this item it takes
  profession
```

Colours:

- **Green:** you know it, or you have the skill to learn it.
- **Red:** your profession, but your skill is too low.
- **White:** your profession; the skill needed isn't known.
- **Grey:** another profession (Shift view only).

Recipes taught by trainers have no skill number: Blizzard's data doesn't include one. Recipes from patterns, plans and formulas do.

"(known)" relies on Flipper having read your recipes, so open each profession window once after installing, and again after learning new recipes.

## Next steps

When one of the item's recipes makes something other recipes use, the most useful of those are listed under it:

```
  Mining: Smelt Copper x1  -> 31 recipes
      Blacksmithing 1: Rough Sharpening Stone (1)
      Engineering 30: Handful of Copper Bolts (1)
```

The count after "->" is every recipe that uses the product. Normally the next-step lines show your own professions only (two at most); with Shift held, every profession (four at most). Only one step is shown: ore to bars to recipes, not further.

## Gear: disenchanting

For armor and weapons, enchanters see what the item disenchants into and the enchants those materials go into:

```
Flipper Vendor it
  Disenchants into Small Glowing Shard
  Enchanting: Enchant 2H Weapon - Minor Impact (1 Small Glowing Shard)
  Enchanting 115: Enchant Shield - Lesser Protection (1 Small Glowing Shard)
  +6 more enchants (hover with Shift held)
```

Results show chances when there is more than one, for example "Strange Dust (75%), Lesser Magic Essence (20%)". They follow the original-era disenchant tables, with estimates for Forever's own rare items, so they can occasionally differ from what you get. Characters without Enchanting see these lines with Shift held.

## Hold Shift for details

Press and hold Shift **before** you hover; the tooltip doesn't redraw if you press it while it's already open. The Shift view adds:

```
  AH after cut 46c
  Sold by vendors: 5c at Corporal Bluth, Stranglethorn Vale (38, 3)
  Market: ~3.2 sold/day, 70% of listings sell (26h watched)
  You: 12 sold, 3 didn't (80%)
```

- **AH after cut:** the fair price (cheapest listing, or the 21-day average when the cheapest is a wild outlier) minus the 5% AH cut.
- **Sold by vendors:** where to buy it, from vendors you've opened and from Questie.
- **Market:** estimated sales from Flipper's full scans; the hours watched say how much to trust it. See [Sales estimates](sales-estimates.md).
- **You:** your own exact results, from Journalator.
- **Every profession's recipes**, up to twenty, and up to four next steps each.

## What each line needs

| Line | Needs |
|---|---|
| Verdict, AH price | Auctionator (or TSM) and a recent scan |
| "(known)", "Craft ..." | Each profession window opened once |
| Recipe lists, next steps, disenchant results | Nothing: ships with Flipper |
| Sold by vendors | Questie, or having opened that vendor |
| Market | Two Full scans 15 minutes to 12 hours apart |
| You | Journalator |

## Turning it off

`/flip tooltip` switches Flipper's tooltip lines off and on. The window and scans are unaffected.

## Known limits

- The tooltip doesn't know whether an item is soulbound, so it may say "Auction it" for something you can't trade. The Bags tab does check.
- "Craft" values the output at the fair price; it doesn't check whether the output actually sells (see the Sold/day column for that).
