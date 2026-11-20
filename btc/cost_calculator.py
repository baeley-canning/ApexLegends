#!/usr/bin/env python3
"""All-in NZD cost of buying bitcoin through every route still open to a NZ buyer.

Every number here was read off a primary source on the date shown in fees.md.
It prints the honest total: trading fee + withdrawal/network cost, the sats that
disappear, and what the price has to do just to break even.

Usage:
    python cost_calculator.py                  # NZ$5,000 at the live rate
    python cost_calculator.py --amount 1000
    python cost_calculator.py --price 113432   # offline / reproducible

This is arithmetic, not advice. Fees change; re-run and re-read fees.md.
"""

import argparse
import json
import sys
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

FALLBACK_PRICE = 113432.0

# pct = percentage fee, fixed_nzd = flat charge, sats = fixed on-chain fee in satoshi
# min/max = NZD order bounds. "blocked_new" = cannot be done as one order on a
# brand-new account. Source column points at fees.md.
ROUTES = [
    {
        "name": "Swyftx bank transfer",
        "pct": 0.0060, "fixed_nzd": 0.0, "sats": 2000,
        "min_nzd": 0.0, "max_nzd": 100000.0,
        "blocked_new": False, "liquidity": True,
        "note": "0.6% Regular tier + 0.00002 BTC withdrawal; NZD rail free, no cap",
    },
    {
        "name": "Flow Crypto single order",
        "pct": 0.0079, "fixed_nzd": 1.50, "sats": 0,
        "min_nzd": 50.0, "max_nzd": 2500.0,
        "blocked_new": True, "liquidity": True,
        "note": "0.79% incl GST + ~$1.50 network; new account capped $1k first / $2k day",
    },
    {
        "name": "Flow Crypto over 3 days",
        "pct": 0.0079, "fixed_nzd": 4.50, "sats": 0,
        "min_nzd": 50.0, "max_nzd": 5000.0,
        "blocked_new": False, "liquidity": True,
        "note": "same rate, 3 x $1.50 network, 3 x price exposure (DCA side effect)",
    },
    {
        "name": "Localcoin ATM (cash)",
        "pct": 0.1900, "fixed_nzd": 0.0, "sats": 0,
        "min_nzd": 5.0, "max_nzd": 9500.0,
        "blocked_new": False, "liquidity": True,
        "note": "~19% markup baked into the rate + network fee; $9,500 per txn cap; tiered ID",
    },
    {
        "name": "CoinFlip ATM (cash)",
        "pct": 0.1700, "fixed_nzd": 5.00, "sats": 0,
        "min_nzd": 20.0, "max_nzd": 2000.0,
        "blocked_new": False, "liquidity": True,
        "note": "~17% markup + ~$5 flat + ~$4 network; markup moves, read the screen rate",
    },
    {
        "name": "Bisq P2P (non-KYC)",
        "pct": 0.0000, "fixed_nzd": 0.0, "sats": 50000,
        "min_nzd": 0.0, "max_nzd": 1e9,
        "blocked_new": True, "liquidity": False,
        "note": "flat ~0.0005 BTC taker + miner fee; no BTC/NZD offers live at check time",
    },
]


def live_price() -> tuple:
    url = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=nzd"
    try:
        with urllib.request.urlopen(url, timeout=8) as fh:
            data = json.load(fh)
        return float(data["bitcoin"]["nzd"]), "coingecko live"
    except Exception as exc:
        return FALLBACK_PRICE, f"fallback constant ({type(exc).__name__})"


def evaluate(route: dict, amount: float, price: float) -> dict:
    sats_nzd = route["sats"] * price / 1e8
    fee = amount * route["pct"] + route["fixed_nzd"] + sats_nzd
    btc_net = (amount - fee) / price
    btc_gross = amount / price
    sats_lost = (btc_gross - btc_net) * 1e8
    out = dict(route)
    out.update(
        fee_nzd=fee,
        net_nzd=amount - fee,
        btc=btc_net,
        sats_lost=sats_lost,
        eff_pct=(sats_lost / (btc_gross * 1e8)) * 100 if btc_gross else 0.0,
        too_small=amount < route["min_nzd"],
        too_big=amount > route["max_nzd"],
    )
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--amount", type=float, default=5000.0, help="NZD to spend (default 5000)")
    ap.add_argument("--price", type=float, help="pin BTC/NZD instead of fetching")
    args = ap.parse_args()

    if args.amount <= 0:
        print("amount must be positive")
        return 2
    if args.price:
        price, source = args.price, "pinned by --price"
    else:
        price, source = live_price()

    print(f"ORDER      : NZ${args.amount:,.2f} of BTC")
    print(f"PRICE      : NZ${price:,.0f} per BTC  [{source}]")
    print(f"BTC at mid : {args.amount / price:.8f} BTC ({args.amount / price * 1e8:,.0f} sat)")
    print()
    head = f"{'route':26} {'fee NZ$':>9} {'net NZ$':>9} {'sats lost':>10} {'eff %':>7}  flags"
    print(head)
    print("-" * len(head))

    rows = [evaluate(r, args.amount, price) for r in ROUTES]
    for r in rows:
        flags = []
        if r["too_small"]:
            flags.append("below minimum")
        if r["too_big"]:
            flags.append("above cap")
        if r["blocked_new"]:
            flags.append("not as one order (new account)")
        print(
            f"{r['name']:26} {r['fee_nzd']:9,.2f} {r['net_nzd']:9,.2f} "
            f"{r['sats_lost']:10,.0f} {r['eff_pct']:6.2f}%  {', '.join(flags) or '-'}"
        )

    print()
    usable = [r for r in rows if not (r["too_small"] or r["too_big"])]
    now = [r for r in usable if r["liquidity"] and not r["blocked_new"]]
    if not now:
        print("No route can execute this amount as one order right now.")
        return 0

    best = min(now, key=lambda r: r["fee_nzd"])
    worst = max(now, key=lambda r: r["fee_nzd"])
    print(f"CHEAPEST NOW: {best['name']} -> NZ${best['fee_nzd']:,.2f} ({best['eff_pct']:.2f}%, "
          f"{best['sats_lost']:,.0f} sat)")
    print(f"DEAREST NOW : {worst['name']} -> NZ${worst['fee_nzd']:,.2f} ({worst['eff_pct']:.2f}%)")
    print(f"SPREAD      : NZ${worst['fee_nzd'] - best['fee_nzd']:,.2f} between them")
    print()
    print(f"BTC has to rise {best['eff_pct']:.2f}% just to break even on {best['name']}.")
    print(f"ONE ORDER   : {best['name']} at NZ${best['fee_nzd']:,.2f}.")

    dead = [r for r in usable if not r["liquidity"]]
    if dead:
        print()
        print("USABLE IN THEORY, NOT TODAY: " + ", ".join(r["name"] for r in dead))
        for r in dead:
            print(f"  {r['name']} would cost NZ${r['fee_nzd']:,.2f} ({r['eff_pct']:.2f}%) "
                  f"- keep as a fallback only if an offer appears.")

    print()
    print("NOTES")
    for r in rows:
        print(f"  {r['name']}: {r['note']}")
    print()
    print("VERDICT: computed from fees.md sources; re-check before ordering.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
