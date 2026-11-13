"""Export price + sales history per item per day to CSV, for review outside the game.

Joins Auctionator's daily prices (decoded by auction-data/decode_auctionator.py into
forever_ah_history.json) with Flipper's full-scan sales estimates (FlipperDB.market.stats in
SavedVariables/Flipper.lua). Both use Auctionator's day numbers (days since 2020-01-01).

Usage:
    python ../auction-data/decode_auctionator.py <Auctionator.lua>    # refresh prices first
    python tools/export_history.py [out.csv]
SavedVariables are only written when you /reload or log out.
"""
import csv
import datetime
import json
import pathlib
import re
import sys

WOW = pathlib.Path(r"C:\Games\Battle.net\World of Warcraft\_forever_\WTF\Account\COLEPWNZ\SavedVariables")
DATA = pathlib.Path(r"C:\Users\igots\Documents\wow-tools\auction-data")
DAY0 = datetime.date(2020, 1, 1)


def parse_lua_assignments(text):
    """Minimal parser for WoW SavedVariables: `Name = <value>` with tables, strings, numbers, booleans."""
    pos = 0
    token = re.compile(r'\s*(?:--[^\n]*\s*)*')

    def skip():
        nonlocal pos
        pos = token.match(text, pos).end()

    def value():
        nonlocal pos
        skip()
        c = text[pos]
        if c == "{":
            pos += 1
            table, index = {}, 1
            while True:
                skip()
                if text[pos] == "}":
                    pos += 1
                    return table
                if text[pos] == "[":
                    pos += 1
                    key = value()
                    skip(); assert text[pos] == "]"; pos += 1
                    skip(); assert text[pos] == "="; pos += 1
                    table[key] = value()
                else:
                    m = re.compile(r'([A-Za-z_]\w*)\s*=').match(text, pos)
                    if m and not text.startswith(("true", "false", "nil"), pos):
                        pos = m.end()
                        table[m.group(1)] = value()
                    else:
                        table[index] = value()
                        index += 1
                skip()
                if text[pos] in ",;":
                    pos += 1
        if c == '"':
            m = re.compile(r'"((?:[^"\\]|\\.)*)"', re.S).match(text, pos)
            pos = m.end()
            return re.sub(r'\\(.)', lambda e: {"n": "\n", "t": "\t"}.get(e.group(1), e.group(1)), m.group(1))
        for word, result in (("true", True), ("false", False), ("nil", None)):
            if text.startswith(word, pos):
                pos += len(word)
                return result
        m = re.compile(r'-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)').match(text, pos)
        pos = m.end()
        n = m.group(0)
        return int(n, 16) if n.lower().startswith(("0x", "-0x")) else (float(n) if any(ch in n for ch in ".eE") else int(n))

    result = {}
    while True:
        skip()
        m = re.compile(r'([A-Za-z_]\w*)\s*=').match(text, pos)
        if not m:
            return result
        pos = m.end()
        result[m.group(1)] = value()


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DATA / "forever_item_days.csv"
    names = {}
    latest = DATA / "forever_ah_prices_latest.csv"
    if latest.exists():
        with open(latest, encoding="utf-8-sig", newline="") as f:
            names = {int(r["item_id"]): r["name"] for r in csv.DictReader(f)}

    prices = {}
    history = DATA / "forever_ah_history.json"
    if history.exists():
        for realm in json.loads(history.read_text(encoding="utf-8")).values():
            for key, item in realm.items():
                if not key.isdigit():
                    continue
                days = prices.setdefault(int(key), {})
                for field in ("h", "l", "a"):
                    for day, v in (item.get(field) or {}).items():
                        days.setdefault(int(day), {})[field] = v

    sales, observed = {}, {}
    saved = WOW / "Flipper.lua"
    if saved.exists():
        stats = ((parse_lua_assignments(saved.read_text(encoding="utf-8")).get("FlipperDB") or {})
                 .get("market") or {}).get("stats") or {}
        observed = {int(d): s for d, s in (stats.get("observed") or {}).items()}
        for item_id, days in (stats.get("items") or {}).items():
            sales[int(item_id)] = {int(d): v for d, v in days.items()}

    rows = 0
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["item_id", "name", "date", "low_copper", "high_copper", "listed",
                    "sold", "expired", "relisted", "hours_watched"])
        for item_id in sorted(set(prices) | set(sales)):
            p, s = prices.get(item_id, {}), sales.get(item_id, {})
            for day in sorted(set(p) | set(s)):
                d = p.get(day, {})
                v = s.get(day) or ({1: 0, 2: 0, 3: 0} if day in observed else {})
                w.writerow([item_id, names.get(item_id, ""), (DAY0 + datetime.timedelta(days=day)).isoformat(),
                            d.get("l") or d.get("h") or "", d.get("h", ""), d.get("a", ""),
                            v.get(1, ""), v.get(2, ""), v.get(3, ""),
                            round(observed[day] / 3600, 1) if day in observed else ""])
                rows += 1
    print(f"{rows} item-days written to {out} ({len(sales)} items with sales estimates)")


if __name__ == "__main__":
    main()
