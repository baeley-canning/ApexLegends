# Privacy — what actually helps and what is theatre

Short version: **you are not anonymous when you buy NZ$5,000 of bitcoin.** You are *unlinked*.
The difference matters, and most privacy advice on the internet optimises the wrong one.

## The two different things

1. **Identity** — who you are to the seller. An exchange or ATM that takes your ID knows. Bank
   transfer reveals your name anyway. Nothing in this kit changes that.
2. **Linkage** — whether the coins you end up holding can be tied to that identity, to your other
   coins, or to each other. **This is the part you control**, and it is entirely about keys and
   addresses, not about Tor.

A VPN does not make an exchange purchase private. It stops the exchange's fraud engine and your
ISP from seeing your IP, which is worth something small. Fresh keys stop your whole future wallet
from being one cluster on a block explorer, which is worth much more.

## Do these, in this order

1. **Generate the wallet offline with `wallet_gen.py` and never reuse a seed.** A seed that has
   only ever received from this one exchange is not linked to you anywhere else.
2. **Withdraw straight to a fresh `bc1` address, never leave the coins on the exchange.** Exchange
   balances are IOUs and are the first thing subpoenaed.
3. **One address per deposit.** The generator hands you five; use index 0 for this buy. Do not
   paste the same address into a second venue later.
4. **Do not consolidate addresses after the fact** in a way that reveals the set, unless you are
   deliberately sweeping to cold storage — then sweep everything at once, not piecemeal.
5. **Keep the passphrase off the same paper as the seed.** Written separately, in two places.
6. **Buy with bank transfer, not card.** A card gives the exchange your card network trail and
   usually costs more. Bank transfer is same-name anyway.
7. **Cash at an ATM** only buys you the absence of a bank-side record; the machine still scans ID
   above the small tier. Same CARF reachability.

## VPN — where it helps, and the leak tests

Use it for the exchange session if you already own one. Free VPNs are worse than nothing only
slightly; if you are paying, Mullvad or IVPN are the ones with audited no-logs claims.

Before the session, with the VPN ON, all of these must pass:

- [ ] `dnsleaktest.com` extended test → resolvers belong to the VPN, not your ISP
- [ ] `browserleaks.com/webrtc` → no local or public address outside the VPN's ranges
- [ ] `ipleak.net` → IP, DNS and timezone all consistent with the VPN exit, no real city
- [ ] Kill switch enabled and **tested** by pulling the VPN down and confirming traffic dies
- [ ] Only the VPN browser profile used — no logged-in Google/Facebook session on the same profile

Practical notes, learned the hard way:

- Pick an exit in a country with no special relationship to NZ if you care; Auckland exit gains little.
- VPN + bank transfer can trip a "new location" fraud hold. Expect one verification email; that is
  normal, not a reason to switch the VPN off mid-order.
- Turn the VPN on **before** logging in, off only after the withdrawal is broadcast, and never log
  in from home IP and VPN IP in the same session.
- Mobile app on cellular is a different IP set and looks like a location change. Pick one and stay.

## What is theatre

- Tor for a KYC'd bank-transfer buy. The exchange sees your name on the deposit regardless.
- A "privacy" wallet brand that still derives addresses from a seed you pasted into a phone app.
- Rotating VPN exits mid-session.
- Paying an ATM premium purely for privacy when a bank account is available.
- CoinJoin before the coins have moved once. Do it later, from a wallet you control, if at all —
  and note that the fee buys linkage-breaking you may already have from fresh keys.

## Tax reality — CARF lands either way

New Zealand has committed to the OECD **Crypto-Asset Reporting Framework**. Exchanges report
NZ-resident customers' balances, acquisitions and disposals to Inland Revenue, with the first
reporting cycle covering the 2026 year and reports landing in 2027. Verify the current status
before relying on it — it has been legislated on a moving timetable.

Consequences:

- Every KYC route in `fees.md` is visible to IRD. Picking one over another is a cost decision,
  not a hiding decision.
- **Keep your own records anyway**: date, NZD amount, BTC amount, fee, address, and the exchange's
  CSV export. IRD wants NZD figures and the exchange's own export is the thing that will be
  matched against you.
- Disposal is a taxable event. Moving coins from the exchange to your own wallet is **not** a
  disposal. Spending, trading or selling is.
- ATM receipts are your only acquisition record if you use cash — photograph nothing, keep the paper.
- There is no de-minimis for crypto in NZ; small buys still count.

## Honest summary

Buying through Swyftx with a fresh offline wallet and a straight-to-your-own-address withdrawal
gives you: no reuse, no exchange custody, no address clustering to your name, and a clean paper
trail for IRD. That is the realistic ceiling. Anyone promising more from a $5k bank-transfer buy
is selling something.
