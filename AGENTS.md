# AGENTS.md — hard rules for any agent working in this repo

Machine: DESKTOP-PPHFJBQ (daily driver, Windows 11 26200, Realtek/Intel, no dev VM slave).
Harness: `_ritual/`. State: `STATE.md`. Milestone 1 = the Javelin/EAAC gate.

These rules exist because an agent in act mode mutated kernel/driver/CI state directly on the
daily driver and **crashed it**, losing ~5 h of work to a snapshot revert. They are not style
preferences. Violating them is a failed task even if the probe "worked".

## R1 — Kernel/driver/CI changes run in the VM first. Host is the last step, never the lab.

- Order is always: **VM bench (VM-A/VM-B, snapshot first) → host.** A recipe that has not passed
  in the VM is not allowed to touch the host.
- "Changes" means anything that can bugcheck or change boot behaviour: `kdu`/BYOVD load, `sc
  create|start|stop` of a driver, `g_CiOptions`/DSE writes, `bcdedit`, `dism` feature toggles,
  `testsigning`/`hypervisorlaunchtype`, CI policy registry (`...\CI\Config`, `...\CI\State`),
  service `binPath` edits, driver file swaps under `System32\drivers`.
- Host-only work that is safe without the VM: screenshots, OCR, window raise, clicks/scancodes,
  `Get-Process`, `sc query`, `bcdedit /enum`, reading existing logs. That is what the harness does.
- If the VM cannot start, say so and stop — do not "just try it on the host because it's quick".

## R2 — Never reboot the host without asking.

A reboot costs the user their session and kills every timer/game window. Boot-flag changes are
batched and end with one reboot the user has agreed to, not a reboot per flag.

## R3 — Every state change needs a read-back, and the read-back is the only verdict.

- `kdu` exit codes are useless (`1` on success *and* failure); "verification succeeded" alone is
  not a verdict (it printed that while the write faulted under VBS). Gate on the *next* observable:
  `sc start` rc, `STATE: 4 RUNNING`, game process alive.
- Write results to a file and read the file. Chat-rendered screenshots are unreliable here; OCR
  text files (`_ocr*.txt`) are the state feed.
- Before mutating: record pre-state (service state, last exit code, `binPath` hash, blocklist, CI
  state, process list). After: re-record. A probe that cannot show both halves is not evidence.

## R4 — Reversibility, always, in the same script.

Every mutation carries its own restore: DSE `0` → back to `6`, driver started by us → stopped by us
unless the state file says "leave RUNNING", registry value set → previous value restored, file
swapped → `.bak` kept. A probe must be safe to re-run.

## R5 — One variable per probe; new number, never overwrite output.

`pNN`/`hNN` monotonic, own output file, `RESULT:`/`VERDICT:` line that names the variable changed.
Stale output read as fresh is the single most common false conclusion in this repo.

## R6 — Stay in the tree; use `_ritual/` helpers.

No ad-hoc one-liners that mutate state inside a chat turn: put it in a script, run the script,
read the output file. `cl.exe` cannot parse `New User` — go through `BuildDriver.ps1`.

## R7 — `PLAN.md` is the only "next step"; `FACTS.md` is the only truth table.

`STATE.md` is append-only history, `HANDOFF.md` is orientation. If a document disagrees with
`PLAN.md` about what to do next, `PLAN.md` wins; if it disagrees with `FACTS.md` about a proven
fact, `FACTS.md` wins and the other file gets a one-line correction. Adding a fourth "next
actions" list is how three sessions in a row each picked a different urgent thing.

## R8 — A probe that cannot change a pixel is infrastructure: batch it, do not schedule it.

The goal is a box on screen (PLAN stages 1-5). Before creating a new `hNNN`/`pNNN`, name the
stage it serves and the pixel it could change. If the answer is "it makes the driver more
correct", it goes in the same sitting as the stage that consumes it, behind one game launch -
not as its own evening.

## R9 — A verdict that skipped the game half is not an in-game verdict.

`h328 ... P3=SKIPPED (game not running)` scored `VERDICT: PASS`. Any line claiming in-game truth
must fail when the game-dependent half did not run; print `SKIPPED` and score `PARTIAL`, never
`PASS`. Same family as h316's "PASS is notepad, not the game" and ov76's desktop-OCR menu.

