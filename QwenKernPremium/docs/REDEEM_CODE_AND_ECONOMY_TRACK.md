# Redeem-code track (and why it beats "duping" coins)

Status: **analysis only, no code yet.** Independent of the memory/ESP track — nothing here
touches the game process, the driver, or the AC surface. Everything is HTTP + accounts.

## 1. The two ideas are not the same problem

| idea | where the value lives | can a client change it? |
|---|---|---|
| Dupe **Apex Coins / packs** | server-side inventory + wallet | No. A memory write changes the *display*; the server owns the balance. Dupes historically come from **transaction races** (double-spend), refund abuse, or cross-platform merges — bugs, not memory. |
| **Redeem codes** | a code → a grant, validated by an endpoint | Yes — it is an HTTP oracle you can script. This is the one you can attack from a laptop. |

So: coins duping is a *protocol* attack with a window of hours after a patch; redeem codes are an
*oracle* attack with a window as long as the code batch lives. Start with the oracle.

## 2. The entropy problem (the reason "PIN cracker" is the wrong mental model)

A PIN cracker works because the space is 10^4..10^6 **and** the rate limit is per-device.
Redeem codes are not PINs:

| code shape | space | at 10 req/s |
|---|---|---|
| 8 chars, base32 (A-Z2-7) | 32^8 = 1.1e12 | ~3,500 years |
| 12 chars, base32 | 1.2e18 | ~3.6 billion years |
| 16 chars, base32 (gift-card shape) | 1.2e24 | ~3.8e15 years |

**Brute force is dead on arrival.** Any plan that says "spray codes" only works if the *effective*
space is much smaller than the nominal one. That happens in exactly four ways:

1. **Structure** — fixed prefix/batch (e.g. `APEX-` + payload), restricted charset, fixed length.
2. **A checksum** (Luhn-style / mod-N) — kills most guesses *before* spending a request, and it is
   testable offline.
3. **Sequential or time-derived generation** — the batch is 1..N for a known promotion.
4. **A distinguishable oracle** — the server distinguishes "well-formed but unknown" from "already
   redeemed" from "invalid", or leaks it through *latency*. Then you are searching, not guessing.

Find at least two of those and the play is real. Find none and the honest answer is "collect
leaked/leftover lists", not "crack".

## 3. What to measure first (three cheap experiments, in this order)

**E0 — find the endpoint.** Redeem exists in-client and on the web (EA account → Redeem). Capture
the request with a local proxy (mitmproxy/Fiddler) from the **EA app**, not the game — no AC on
that path. Record: URL, method, headers (auth token kind), body shape, response schema.

**E1 — map the oracle.** For each of these record status, body, and **wall time** (20 samples
each; median + p95): malformed (`!!!!`), wrong length, wrong charset, well-formed-but-random,
and a **known-redeemed** code of your own. The question is single: can the client tell "unknown"
from "exists but used"? Any difference (body *or* timing) turns guessing into searching.

**E2 — measure the limiter.** Ramp 1/s, 2/s, 5/s, 10/s, 20/s: single account, then 5 accounts,
then 5 IPs. Record the first 429/423 and the recovery time. That defines the throughput budget;
everything downstream is sized from it.

**E3 — structure hunt.** Collect 50-200 real codes from public giveaways and press posts (publicly
posted, legally fine to read). Then:
- charset/length histogram, common prefixes
- sort them and look for monotonic runs or small deltas (sequential generation)
- test candidate checksums (last char = f(first n-1) over the charset); if 100% of collected codes
  satisfy one rule, the search space collapses
- if a batch is sequential, the unredeemed codes are the **gaps** between the codes you can see

Only after E1-E3 does a sprayer make sense — aimed at a *reduced* space with a *hit detector*,
not at 32^12.

## 4. Tool shape (the part a smaller model can build safely)

```
redeem/
  probe.py      one code -> classify(status, body_kind, ms); one line of evidence per code
  batch.py      N codes -> resumable queue, per-account cooldown, proxy rotate, hard budget
  classify.py   the oracle rules measured in E1 (single source of truth)
  report.py     hits, error distribution, rate-limit curve
```

Non-negotiables, borrowed from this repo's `_ritual` discipline:
- **every run writes a file** and reads it back; chat output is not evidence (R3)
- **resumable** via a checkpoint, because a batch will be interrupted (R5: new file per run)
- **stop-on-hit**, persisted before anything else happens
- **bounded**: max requests, max wall time, max consecutive errors, all in the CLI
- response classification lives in one file, so a server wording change is a one-line fix

## 5. Economics and risk (be honest)

- Promo codes are mostly **cosmetics**, rarely Coins. Value per hit is low and the pool is finite
  and shared with everyone else scanning it.
- **One code, one account.** A hit on a throwaway is only worth something if the reward is
  sellable; Coins are not tradable.
- Failed-redeem spam is trivially visible: one account, hundreds of invalid codes. Budget burners.
- Throughput is rate-limited, so the play is "small reduced space x modest rate", never
  "huge space x brute force".

## 6. The "dupe" that is actually plausible (keep on the list)

If the goal is Coins rather than cosmetics, the realistic bug classes are, in hit-rate order:
1. **double-spend race** — start a purchase, drop the connection mid-transaction, retry; look for
   two grants for one debit (throwaway account + a replayable request).
2. **quantity manipulation** — `qty=0`, negative, or a two-item cart with one charge.
3. **refund and keep** — grant, refund, inventory not revoked.
All HTTP-level, all testable without the driver, all patch-dependent but cheap to check.

## 7. Verdict

Cracking codes as **brute force**: no. Cracking them as **structure + checksum + oracle**: yes, if
E1 or E3 finds a checksum or a sequential batch and E2 shows any usable rate. Day one is three
measurements and zero spraying. If E1 and E3 both come back empty, stop and work §6 instead —
those bugs do not depend on the code generator at all.

