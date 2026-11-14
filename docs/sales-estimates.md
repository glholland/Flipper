# Sales estimates

The Sold/day columns and the "Market" tooltip line are estimates. The game tells you about your own sales and nothing about anyone else's, so Flipper infers sales from listings that disappear.

## How it works

1. **Full** downloads every listing on the AH and saves a snapshot: for each item, how many units are listed at each price and how long they have left.
2. The next full scan is compared with that snapshot. For every listing that has gone:
   - **Expired** if it could have run out of time. A listing shown as "2 to 12 hours left" may have expired once 2 hours have passed.
   - **Cancelled** if a cheaper listing of the same item is still up. Buyers take the cheapest first, so a dearer one that vanished was pulled.
   - **Sold** otherwise.
3. Counts are stored under the day of the second scan and kept for 14 days. Sold/day is the sold count divided by the time watched.

Scans must be between 15 minutes and 12 hours apart to be compared. After 12 hours any listing could have expired, so nothing can be learned.

## How far to trust it

Use Sold/day to rank items against each other, not as a count.

- **Undercut reposts look like sales.** A seller who pulls the cheapest listing and reposts it lower is counted as sold. The game does not name other sellers, so the two cases look the same.
- **Long gaps undercount.** With 4 hours between scans, only listings that had 12+ hours left can count as sold; the rest are "expired".
- **Short watch times exaggerate.** One 2-hour comparison scaled up to a day is noisy. The tooltip shows hours watched.

For the best numbers, run a full scan on most AH visits, ideally an hour or two apart.

Your own results are exact: with Journalator installed, the Shift tooltip shows "You: N sold, M didn't".

## Fair price

Wherever Flipper values something you would sell, it uses a fair price: the cheapest listing, unless that is more than twice the 21-day average, in which case the average. One optimistic listing does not make a market.

Prices Auctionator has not seen for over 7 days are ignored.
