# Troubleshooting

**No Flipper tab at the auction house.** The tab is added through a library that ships with Auctionator. Check Auctionator is enabled, then use `/flip` for the standalone window in the meantime.

**Lists are empty or say "no price".** Run an Auctionator scan. Flipper ignores prices not seen in the last 7 days.

**Crafts tab is empty.** Open each profession window once.

**Sold/day shows "-".** It needs two full scans 15 minutes to 12 hours apart, and at least an hour watched in total. See [Sales estimates](sales-estimates.md).

**"Full" is greyed out.** Full scans are limited to one every 15 minutes; the button shows the time left.

**Buy from vendor has few rows or no locations.** Install Questie, or open vendors as you travel; Flipper remembers their stock and position.

**A new version didn't load.** Restart the game. `/reload` only picks up changes to files the game already knew about.

**Lua errors.** Paste the full error text into an issue, with what you clicked before it appeared.

## Action bars vanish or "Interface action failed because of an AddOn"

This is taint: an addon interfered with Blizzard's protected UI code. Flipper is linted against the usual cause (leaked globals), but any addon can do it. To find which:

1. Type `/console taintLog 1`, then `/reload`.
2. Play until it happens again, then `/reload` so the log is written.
3. Open `World of Warcraft/_forever_/Logs/taint.log`. Each entry names the addon responsible.
4. Turn logging off with `/console taintLog 0`.
