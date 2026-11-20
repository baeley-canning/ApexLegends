# Fees — every route, from primary sources

Read **2026-11-19**. Every figure below came from the operator's own page or API, not a
comparison site, unless the row says otherwise. Re-read this file before ordering; fees move
and a stale number here is the normal way to get robbed.

`cost_calculator.py` is the arithmetic over these numbers. It is only as good as this table.

## The table

| Route | Headline | All-in on NZ$5,000 | Can it be one order? | Source |
|---|---|---|---|---|
| Swyftx, NZD bank transfer | 0.6% trade + 0.00002 BTC withdrawal | **NZ$32.27 (0.65%)** | Yes — no min, no max, $0 deposit fee | Swyftx fee API for the 0.00002 BTC; support article for the 0.6% start tier |
| Flow Crypto | 0.79% incl GST + ~$1.50 network | NZ$41.00 (0.82%) | **No** — new-account deposit limits | flowcrypto.co.nz/fees and /help/cheapest-way-to-buy-bitcoin-nz |
| Flow Crypto, spread over 3 days | same + 3 network fees | NZ$44.00 (0.88%) | Yes, but 3 orders and 3 price exposures | same |
| CoinFlip ATM, cash | ~17% markup + ~$5 flat + ~$4 network | NZ$855 (17.1%) | No — roughly $2,000 per transaction | coinflip.nz/coinflip-bitcoin-atm-charges (own 2026 audit) |
| Localcoin ATM, cash | ~19% markup inside the rate | NZ$950 (19%) | No — NZ$9,500 per-transaction cap | exchangecrypto.nz/reviews/localcoin (Sept 2026); crypto.kiwi.nz/bitcoin-atm (Oct 2026) |
| Bisq P2P | ~0.0005 BTC taker + miner fee | NZ$56.72 in theory | No — **no BTC/NZD offers live** | Bisq client, book checked empty |

## The one that decides it

Swyftx is the cheapest route in the table and the only one that can take the whole NZ$5,000 in one
order on day one. Flow's headline (0.79% incl GST) is close and its deposit caps are the interesting
part: NZ$1,000 first deposit, NZ$2,000 per day, NZ$5,000 per week, for the first 30 days, per its
own limits page. A single $5k order is impossible on a new Flow account. Swyftx has no such cap on
bank transfers.

So the honest ranking for *this* job:

1. **Swyftx, one order** — NZ$32.27, done today, selfie-only verification.
2. **Flow over 3 days** — NZ$44.00, close second, and DCA-ish.
3. **ATM** — NZ$855–950. Only worth it if the point is cash and no bank trail.
4. **Bisq** — worst of both: ~1.13% on taker fee alone *and* no BTC/NZD offers live.

## What is still not measured

- **Swyftx spread.** Their quote is server-side and the page is JS-rendered. Measure it: open the
  buy screen for NZ$500, note their BTC/NZD rate, compare to an index at the same second. Anything
  over ~0.3% means the real cost is 0.6% + that, and Flow over 3 days wins instead.
- **Flow spread.** Same method, same page. Flow claims the quote is live; verify rather than believe.
- ATM markups move with volatility. The number that binds you is the one on the kiosk screen —
  compare it to an index *on your phone* before you insert notes.

## How these were established (so it can be redone)

- Swyftx: `GET` on their public fee endpoint returned BTC withdrawal `0.00002`; a support article
  states 0.6% for the Regular tier and that the spread is not tier-dependent. MoneyHub's `0.0005`
  BTC withdrawal figure is **wrong** by 25x — do not use it.
- Flow: fees page gives 0.79% incl GST and a worked $1.50 network fee; the deposit-limit numbers
  come from the limits page, all first-party.
- ATMs: Localcoin's own NZ fee page renders its chart client-side and yields only prose ("a flat
  fee and a transaction fee"), so the markup figures above are third-party audits with dates. Both
  are consistent at 16–19%, which is the industry band. Treat ATM numbers as ±2 points.
- Bisq: client book for BTC/NZD, checked twice on 2026-11-18/19, zero offers both times.

## Rules of thumb that survived

- Percentage fees scale, flat fees do not: at NZ$800 the CoinFlip flat+network pushes it from 17.1%
  to 17.6%, so it edges ahead of Localcoin's flat 19% on small amounts while both stay ~20x Swyftx.
- Withdraw to your own wallet in the same sitting as the buy. An exchange balance is not bitcoin.
- 0.00002 BTC is NZ$2.27 at NZ$113k — under 0.05% of the order. Anyone quoting 0.0005 BTC is
  charging 12x more than Swyftx actually does.
