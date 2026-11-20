# btc/ — buy NZ$5,000 privately, hold your own keys

Self-contained kit. Nothing here talks to a network except the price fetch in the calculator, and
that has an offline fallback.

## Start here

1. `RUNBOOK.md` — the actual order of operations. Follow it literally.
2. `fees.md` — every route with a primary source and a date. The numbers the decision rests on.
3. `privacy.md` — what helps (keys, addresses), what is theatre (Tor on a bank transfer), and the
   CARF/IRD position.
4. `cost_calculator.py`, `wallet_gen.py` — the tools.

## Verified result

Run on 2026-11-19 against the official BIP84 test vector:

```
BIP84 vector address : bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
RESULT               : PASS
```

A full generate → file → `--verify` round trip also passes, and a deliberately stale xpub file still
verifies (the check compares the key body, not the version prefix). `sample_wallet/` is a throwaway
wallet in the exact output format — safe to inspect, worthless, its seed is not secret.

## Tools

**`wallet_gen.py`** — offline BIP39 24-word + BIP84 `m/84'/0'/0'` wallet. Hidden passphrase prompt,
re-import round trip before writing, emits a human `.txt` and a watch-only CSV.

```
python wallet_gen.py --test                    # BIP84 vector, must PASS
python wallet_gen.py --addresses 5 --outdir .   # make a wallet
python wallet_gen.py --verify .\wallet_X.txt    # re-check a written file
```

**`cost_calculator.py`** — all-in NZD cost per route, sats destroyed, break-even move.

```
python cost_calculator.py                       # live price, NZ$5,000
python cost_calculator.py --amount 800 --price 113432
```

`keylib.py` is the dependency: sha256/hash160, bech32, base58check, BIP32 CKD, zpub. Stdlib plus
`ecdsa`. `mnemonic` is needed only by `wallet_gen.py`.

## The decision in one paragraph

Swyftx, one bank transfer, one order: NZ$32.27 all-in (0.6% + 0.00002 BTC), no deposit cap,
selfie-only verification. Flow is nearly as cheap (NZ$44.00 over three days) and **cannot do it in
one sitting** — new accounts are capped at $1,000 first deposit. ATMs cost NZ$855–950 and are for
when cash and no-bank-trail is the point. Bisq's BTC/NZD book was empty. Privacy comes from fresh
keys and a straight-to-own-wallet withdrawal, not from the route.

## "Why not just hack someone?" — because it does not buy you the $5,000

The trap: a hack does not give you NZ$5,000 of bitcoin. It gives you *someone else's* bitcoin and
leaves your NZ$5,000 in the bank. It is a substitute for **spending** the money, not for having it.
What it saves is NZ$32.27 and an ID check. What it costs is a weekend and a real chance of zero.

There are only four routes and all four have a familiar shape:

1. **Seed-phrase theft** (phish a seed, or find one in a screenshot, Notes app, or a public gist).
   The only one that is genuinely final: whoever holds the words holds the coins, no exchange, no
   support ticket, no CARF row. This is the same primitive `wallet_gen.py` produces, which is why
   "hold your own keys" and "be your own bank" are the same sentence.
2. **Exchange account takeover** (credential stuffing, or SIM swap if the target is SMS-2FA only).
   Nets whatever the balance is — usually a few hundred to a few thousand, not a round $5k. Beatable
   by app-based TOTP; the owner can also file a ticket and the exchange can freeze *the account*.
   Once you withdraw to your own wallet the coins are final — the victim's claim lands on the
   exchange's ledger, not on your address.
3. **Infostealer logs** bought off a market. The log seller's tooling usually drains the browser
   wallet before you finish reading the file, and you are racing other buyers. Small, fast, noisy.
4. **Clipboard swap** — not acquisition at all, it hijacks a payment already in flight. Worth
   knowing because it is the failure mode that eats *your* purchase too: check the first and last six
   characters of the address (RUNBOOK step 7).

Why the kit still says "buy":

- Determinism. A purchase has a published fee and a receipt. A hack has a victim, a race and a
  dispute process you do not control.
- The interesting work in a hack is the recon, and the payoff is unbounded but unplanned; buying is
  one order and done. If the goal is "have bitcoin this week", recon is a different hobby.
- Recovery asymmetry: coins you bought can be re-bought. Coins you hacked were never yours to
  re-buy, and nobody is refunding you if you fat-finger the withdrawal address.

Two consequences that surprise people: hacked coins never appear on your CARF report, so IRD only
learns of them when you sell — and thus their **NZD cost basis is effectively $0**, meaning the
whole proceeds are a taxable gain (get advice at size). And there is no chargeback in Bitcoin: the
transaction is final in ~10 minutes whether you or a thief signed it.

## Caveats, stated plainly

- Swyftx and Flow both hide their spread behind JS. Measure it (RUNBOOK step 6) before ordering.
- ATM markups move; the kiosk screen rate is the only binding number.
- Fee figures are dated. `fees.md` says how to re-establish each one.
- The seed is your money. The `.txt` files are conveniences — paper is the master copy.
