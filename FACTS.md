# FACTS — one page, PROVEN vs CANDIDATE (updated 2026-11-07)

If a value here is not marked PROVEN it must not be used to draw anything.
Evidence for every line is in the file named next to it.

## Transport

| Thing | Value | Status | Evidence |
|---|---|---|---|
| Own driver read path | `\\.\ApexDrv`, ABI v14, `BASE`/`READ8`/`READBUF`/`WRITE` | **PROVEN on own process** | `_ritual/h328_vadbase.out` (P1+P2 PASS) |
| Own driver vs live game | — | **NOT PROVEN** (h328 P3 skipped, game down) | `_ritual/h328_vadbase.out:17` |
| Game + driver coexistence | 34.9 min alive, apexdrv RUNNING, DSE restored | **PROVEN (one boot)** | `STATE.md` 604–626 (G1) |
| Third-party transport | gdrv3 `\\.\GIOV3` `0xC3502014` raw **physical** read | PROVEN | `ext/gio.py` |
| Usermode RPM/WPM/VAlloc into game | refused per-op (87 / 5 / 0xC000000D / 0xC0000022) | PROVEN, closed | PHASE1 §11.1–11.7 |
| Module base, no RPM | VAD image-section walk + section name | PROVEN on own process | `_ritual/h328_vadbase.out` P1 |

## Offsets (`QwenKernPremium/include/apex_offsets_generated.h`)

| Name | Value | Status |
|---|---|---|
| `ENTITY_LIST` | `0x23F6A90` | CANDIDATE (two sources agree, never validated live) |
| `LOCAL_PLAYER` | `0x01E7D4B8` | CANDIDATE |
| view/projection matrix | `0x1B4DFA0` | CANDIDATE (`ext/h320_va.py`) |
| view matrix (old) | `0x022EE01` | **WRONG** — it is the RVA of `VTP_GetEngineTraceClient` (code) |
| entity origin | `+0x330` | CANDIDATE (`h320_va`) vs `+0x258` in `memory.h` |
| entity hp / shield | `+0x5E0` / `+0x5E8` | CANDIDATE |
| entity team / name / alive | `+0x10E8` / `+0x10F0` / `+0x5DC` | CANDIDATE |

**Do not trust either set until Stage 2 validates numerically.** `features.cpp` currently uses
the old set, so even a perfect entity list would draw nothing — that is a known bug, fixed in Stage 2.

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
