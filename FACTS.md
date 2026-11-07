# FACTS — one page, PROVEN vs CANDIDATE (updated 2026-11-07)

If a value here is not marked PROVEN it must not be used to draw anything.
Evidence for every line is in the file named next to it.

## Transport

| Thing | Value | Status | Evidence |
|---|---|---|---|
| Own driver read path | `\\.\ApexDrv`, ABI v14, `BASE`/`READ8`/`READBUF`/`WRITE` | **PROVEN on own process** | `_ritual/h328_vadbase.out` (P1+P2 PASS) |
| Own driver vs live game | `BASE`+`READ8`+`READBUF` on pid 24360, 60/60 samples, alive at +60 s | **PROVEN 07/11 20:57** | `_ritual/qk_probe_game_20261107_205717.txt` (VERDICT: PASS) |
| Game + driver coexistence | 34.9 min alive, apexdrv RUNNING, DSE restored | **PROVEN (one boot)** | `STATE.md` 604–626 (G1) |
| Third-party transport | gdrv3 `\\.\GIOV3` `0xC3502014` raw **physical** read | PROVEN | `ext/gio.py` |
| Usermode RPM/WPM/VAlloc into game | refused per-op (87 / 5 / 0xC000000D / 0xC0000022) | PROVEN, closed | PHASE1 §11.1–11.7 |
| Module base, no RPM | VAD image-section walk + section name | PROVEN on own process | `_ritual/h328_vadbase.out` P1 |

## Offsets (`QwenKernPremium/include/apex_offsets_generated.h`)

**MEASURED 07/11 21:0x against build 2026-10-24 (pid 24360): the whole table is STALE.**
Every read below succeeded (the pages are mapped) and every value was garbage — so the fault is
the table, not the transport. Evidence: `_ritual/qk_ents_run1.txt`, `_ritual/qk_hunt_run2.txt`.

| Name | Value | Status after measurement |
|---|---|---|
| `ENTITY_LIST` | `0x23F6A90` | **WRONG** — holds `0x5E2C1480475A9C4`, not a pointer; the 7 canonical qwords within ±0x1000 all point at unmapped pages (`0xC0000005`) |
| view matrix (B) | `0x1B4DFA0` | **WRONG** — 16 finite floats but values like `2.9e23`; no matrix-shaped window within ±0x4000 |
| view matrix (A) | `0x022EE01` | **WRONG** — code, as suspected; zero matrix windows in ±0x4000 |
| entity origin / hp / shield / team / name | both candidate sets | **UNTESTED** — no valid entity was ever reached, so neither set has been scored live |
| `LOCAL_PLAYER` | `0x01E7D4B8` | **UNTESTED** |

Consequences: `features.cpp` cannot possibly draw with this table, and neither can any port of it.
The offsets have to be re-derived for the current build (`qk_hunt --image` + RE / a verified
patch-day list), then validated by projecting a known world point onto a known dummy.


## What has actually been seen

| Claim | Where | Status |
|---|---|---|
| Health/shield drops under wingman + nade | `temp/p65_run_20261107_180706.txt`, `…181825.txt` | PROVEN (physical-address sweep; addresses die at reboot) |
| D3D12 overlay + menu renders | `_ritual/ov54`, `ov56` (late-queue, game-queue order) | PROVEN offline |
| Hook loader maps a DLL | `_ritual/ov79_hooklog.txt` — into **explorer.exe** | PROVEN (not the game) |
| Box over a real player | — | **NEVER** |
| External overlay window | — | **DOES NOT EXIST** (no `WS_EX_LAYERED/TOPMOST` in `src/`) |
| Aimbot | — | STUB (`features.cpp:108`) |

## Known traps (each already cost a day)

- `overlay_test.exe` is an **offline regression harness** (opaque `WS_OVERLAPPEDWINDOW`,
  three hardcoded boxes at `overlay_test.cpp:762-765`, auto-exits). It is not the product.
- p65 seed files are **physical** addresses (`temp/p64_seed19.txt` = `0x4de2c6c58`); stale after
  every reboot. `p64_offline.py` is the only no-game way to re-check the verdict logic.
- `bcdedit` needs elevation to read; `sc query` does not.
- Chat-rendered output is unreliable — always write the file and read the file (R3).
