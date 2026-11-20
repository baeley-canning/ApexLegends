# New test account — runbook (19/11)

The testing account is banned. This file is the order of work to get a usable one back,
and the rules that stop the next ban from costing a week of evidence.

## What is actually proven about the ban

From EA's own client log (`%LOCALAPPDATA%\Electronic Arts\EA Desktop\Logs\EADesktopVerbose.bak`,
kept as `_ritual/_t16_banline.txt`):

- `user.auth.ends` → `"error":"AuthCodeError_UserAccountStatusInvalid (105113)"`, `status=failure`
  — refused by `accounts.ea.com` at token time, after the auth code was already issued (302).
- `error [ErrorAuthorizationGameBan]`, telemetry `ec-10901`, dialog
  `errorCode=[10901], title=[Your account has been banned]`, EbisuSDK
  `<ErrorSuccess Code="-1577058285" Description="User is banned"/>`.
- Two occurrences: 18/11 18:03:44 and 18/11 18:12:09. Active EAID **1021383419690**
  (created 03/11 ~07:06, last Apex profile write 19/11 07:12), and its EA app user file
  carries `user.gamebanmodaldisplayed=1` (`_ritual/_account.txt`).

**It is an account-level ban, not a device ban** — the flag is per-account state returned by
the account service, and this box has authenticated **three** different EAIDs
(`_ritual/_account.txt`: 1021383419690 active/banned, 1024381792624 last used 02/11,
1016623179481 last used 12/08). Both clean ones still have no ban flag.
Not proven until a fresh login succeeds — that is exactly what step 2 is for.

## Order of work

1. **Stamp the account.** `_ritual/account.ps1` → `_ritual/_account.txt`. Already run 19/11
   09:26. Rerun after every switch; cite it in any in-game evidence.
2. **Cheapest test first: the 02/11 account (EAID 1024381792624).** EA app → sign out → sign
   in as that one → launch straight into the **firing range** (not a match) → 10 min → quit.
   - Survives with nothing of ours running → the box is fine and we have a working account for
     the `--emit` work today, for free.
   - Refused at sign-in with the same 10901 → go to step 3.
3. **If both older accounts are dead, make a new one.** It is free and it is not a download:
   Apex is F2P and already installed at `C:\Program Files\EA Games\Apex`. Signup is on the EA
   site or the EA app's own form, needs an email you can actually open (the verification code is
   time-limited). Apex on a fresh account starts at the tutorial → firing range.
4. **Control arm (R3 + R9, no exceptions).** Fresh account + **nothing of ours open** — no
   `qk_*`, no `gio` client, no kdu; `gdrv3` stays resident because it always is. One range load,
   10 min, quit cleanly. Then `/account.ps1` and record survival.
   - Survives → the ban was the account, the transport is not what is being punished. Proceed.
   - Banned again within hours → device dimension after all (HWID/board/driver signature):
     stop the feature work, that becomes its own stage.
5. **Only then** resume the producer (`qk_va --emit`), one action per account, ESP and aim on
   separate sittings so a ban points at one change.

## Traps

- The EA app is single-session and the game kicks the other session. Sign the banned account
  **out** before signing the new one in, or every launch bounces.
- Do not create the new account with the banned address — one email serves one EA account. Use
  an alias (`you+apex2@…`) or a second mailbox. Aliases are fine; EA does not need them
  unlinked.
- Do not use a disposable-mail service that cannot receive the code within its window.
- Do not test on the new account with the old `--driver` apexdrv path *and* gdrv3 in the same
  session and then wonder which one flagged.

## Rules this adds to the repo

1. Every in-game evidence file names transport **and** account (`_ritual/_account.txt`).
   Transport-only was enough before the ban; it is not any more.
2. A ban is a gate outcome with a date, an EAID and the running process list — not an accident.
   Log it in `STATE.md` the same day.
3. One account, one variable. Nothing is measured as "the cheat" on a single account twice.
4. `qk_va --emit` must put the account stamp into its `meta` block, so a produced file is
   self-identifying.
