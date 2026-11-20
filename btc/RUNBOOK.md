# Runbook — NZ$5,000 of bitcoin, without losing it

Order matters. Every step has a **check** that must pass before the next one, because the failure
modes here are unrecoverable (wrong seed written down, address pasted from a chat window, coins
sent to a chain that is not Bitcoin).

Estimated time: 90 minutes, of which 20 are verification. Cost at the pinned price: **NZ$32.27**.

## 0. Decide the price you will accept

```powershell
cd 'btc'
python cost_calculator.py                     # live rate
python cost_calculator.py --price 113432      # reproducible
```

**Check:** the CHEAPEST NOW line says Swyftx at roughly NZ$32. If it does not, the market or the
fees moved — re-read `fees.md` and pick again before going further.

## 1. Make the wallet, offline

Disconnect Wi-Fi/Ethernet first. Nothing below needs a network.

```powershell
python wallet_gen.py --addresses 5 --outdir .
```

- Choose a **passphrase** you will not forget. It is a second factor: seed alone is not enough to
  spend. Lose it and the coins are gone forever — there is no reset.
- It prints 24 words. Write them **by hand, in order, on paper**. Not in a photo, not in Notepad,
  not in a password manager on this machine.

**Check:** the run ends `VERDICT : PASS (checksum + re-derivation round trip)`. Anything else and
you start again with a new wallet — do not "fix" a mnemonic by hand.

## 2. Prove the paper works

```powershell
python wallet_gen.py --verify .\wallet_<stamp>.txt
```

**Check:** `VERDICT : PASS - file intact`. This re-derives from the written words, which is the
thing a restore actually does. Now do it once by hand: type the 24 words into a second wallet
application (Sparrow or Electrum, both offline-capable) plus the passphrase, and confirm address
index 0 matches the file. If they differ, stop — you have a transcription error while it is still
cheap.

## 3. Watch-only import

In Sparrow/BlueWallet, import the **zpub** from the file, network Bitcoin, script type native
segwit. The watch-only wallet can see balances and generate addresses but cannot spend.

**Check:** the watch-only wallet shows the same five addresses as the CSV. From here on, never
type the seed into anything network-connected unless restoring.

## 4. Store the paper

Seed and passphrase on **separate sheets, separate places**. Neither sheet alone is spendable.
Move the `.txt` and `_watch.csv` off this machine onto a USB stick or delete them, and keep the
seed sheet as the master.

## 5. Exchange side (Swyftx)

1. Sign up with your real name and address. Verification is selfie + ID, no bank statement.
2. Deposit NZ$5,000 by **bank transfer** into the NZD account they show. No fee, no cap.
   Reference exactly what they tell you to reference.
3. Wait for the deposit to land and clear.

**Check:** NZD balance equals NZ$5,000. If there is a hold, do not place the order yet.

## 6. Measure the spread before you commit

Open the buy screen for NZ$500. Note their BTC/NZD rate. Open any index at the same second.

**Check:** their rate is within ~0.3% of the index. Wider than that and the true cost is 0.6% +
spread — better to abort and use Flow over three days (step 9).

## 7. Buy and withdraw in one sitting

1. Place a market buy for the full NZ$5,000 at the Regular tier (0.6%, i.e. NZ$30).
2. Withdraw **all** of the BTC to address index **0** from your file. Network: Bitcoin. Fee
   0.00002 BTC.
3. Copy the address from the file, then re-read the first six and last six characters against the
   screen before confirming. Never copy an address from a chat window.

**Check:** the withdrawal shows a transaction ID. Paste it into mempool.space and confirm the
output address matches index 0 exactly.

## 8. Confirm on the watch-only side

**Check:** the watch-only wallet shows the incoming amount and the deposit address. One
confirmation is enough for a first check; wait for six before calling it done. Record: date, NZD
in, BTC out, both fees, TXID, address. Save the exchange's CSV export.

**VERDICT is only PASS when all three hold:** coins in the watch-only wallet, TXID output matches
index 0, and the record exists in your own file. A buy with no withdrawal is not done.

## 9. Fallbacks

- **Flow Crypto, 3 days:** NZ$44.00. $1,000 day one, $1,000 day two, remaining $3,000 on day
  three (limits are $1k first / $2k day / $5k week for 30 days). Withdraw each tranche to the
  next unused address index as it lands, and note that three buys means three average prices.
- **ATM, cash:** NZ$855–950. Find the machine first, check the on-screen rate against an index
  on your phone, keep the receipt. Localcoin caps NZ$9,500 per transaction and tiered ID starts
  low; CoinFlip caps around $2,000 and would need three visits.

## 10. When it goes wrong

| Symptom | Cause | Move |
|---|---|---|
| `FAIL: re-derived key differs` | library or transcription bug | new wallet, do not proceed |
| `FAIL - mnemonic checksum invalid` | one word misread (`fuzzy` for `fury`) | fix against the BIP39 wordlist, re-verify |
| Bank deposit held | new payee / VPN / location change | answer the verification email, do not open a second account |
| Withdrawal "pending review" | first withdrawal, large amount | support ticket, give TXID if present, do not cancel and re-buy |
| Spread blows out | volatility | wait an hour; the fee is fixed, the price is not |
| Price drops 10% after buying | normal | nothing. You own bitcoin now. |

## After the fact

- Do not move the coins again for no reason; each move is a fee and another address link.
- Log the acquisition for IRD now, while you remember the numbers. CARF means the exchange's copy
  will reach them anyway, and your own record is what makes the return easy.
- Re-run `--verify` on the file whenever you have touched the paper.
