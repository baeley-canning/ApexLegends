# FACTS — one page, PROVEN vs CANDIDATE (updated 2026-11-07)

If a value here is not marked PROVEN it must not be used to draw anything.
Evidence for every line is in the file named next to it.

## Transport

| Thing | Value | Status | Evidence |
|---|---|---|---|
| **apexdrv v16 DTB** | `EPROCESS+0x28`, one IOCTL, no attach | **PROVEN 07/11 22:03** | `_ritual/qk_va_drv1.txt` (`dtb=0x3AD092000`) |
| **apexdrv v16 PHYS read** | `MmCopyMemory(MM_COPY_MEMORY_PHYSICAL)` 1..0x1000 B | **PROVEN 07/11 22:03** | same file: MZ + `SizeOfImage=0x344000` read through the walk |
| gdrv3 physical read | `\\.\GIOV3` `0xC3502014` (`MmMapIoSpace`) | works for ordinary pages; **fails on some page-table frames** (`1450`) | `temp\_patest.out` |
| Usermode RPM/WPM/VAlloc into game | refused per-op (87 / 5 / 0xC000000D / 0xC0000022) | PROVEN, closed | PHASE1 §11.1–11.7 |
| apexdrv attach reads (v14) | `KeStackAttachProcess` per IOCTL | works, but the game dies in 14 s–4 min after bursts | STATE 21:1x |
| apexdrv v14 on the LIVE game | `BASE`+`READ8`+`READBUF`, 60/60 samples, alive at +60 s | **PROVEN 07/11 20:57** | `_ritual/qk_probe_game_20261107_205717.txt` (VERDICT: PASS) |
| Game + driver coexistence | 34.9 min alive, apexdrv RUNNING, DSE restored | **PROVEN (one boot, 03/11)** | `STATE.md` 604–626 (G1) |


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


## Read-primitive survival (the finding of 07/11 night)

EAAC does not crash the game — it **terminates** it: `EA Javelin Anticheat` event 1000,
`ExitType: 0x322327458D1ED790`. Timestamps vs our probes (`_ritual/qk_*`, Application log):

| time | what happened |
|---|---|
| 20:57:17→20:58:18 | `qk_probe` 60 s / 66 reads — game **alive** at the end |
| 21:00:30→21:02:41 | `qk_ents` + `qk_hunt` ×2 (attach-heavy walks) |
| **21:02:39** | **killed** |
| 21:09:40→21:11:15 | new pid: image scan (57,272 READBUFs), `qk_ents`, `qk_hunt --wide` (8 MB + 8,192 READ8s) |
| **21:11:29** | **killed**, 14 s after the last scan |

Controls that separate driver from read shape:
- **driver resident, idle** → tolerated for **34.9 min** (G1, 03/11 23:29, zero refusals).
- **gdrv3 physical reads (9 GB swept, p65)** → **no kill**: zero Javelin 1000 events between 13:08 and 20:00 on 07/11, i.e. across both 18:07 and 18:18 certs.
- **apexdrv reads, which `KeStackAttachProcess` per IOCTL** → killed in 14 s–4 min, **2 of 2** instances tonight.

⇒ **Hypothesis (strong, one control short of proven): the fingerprint is the per-request process attach,
not the bytes read.** Implication: an ESP at ~200 reads/frame must either (a) do **one attach per batch**
(a new IOCTL that copies 64–1024 values inside a single attach), or (b) read **physically** (page-table
walk + `MmCopyMemory(MM_COPY_MEMORY_PHYSICAL)` / `MmMapIoSpace`), zero attach — the gdrv3 shape that
has never been killed.

**Decisive control (free, do it first):** play ≥10 min with apexdrv resident and **zero** qk_probes.
Survives → the read shape is the trigger. Killed → the resident v14 driver itself is, and G1's 34.9 min
was a different build/config.

### Decision taken 07/11 21:4x — zero-attach on the surviving transport

The evidence is lopsided, so the read layer moved off apexdrv's attach path **before** any ESP work:

| option | cost | evidence it survives |
|---|---|---|
| batch IOCTL (one attach per N reads) | driver change, VM-first (R1) | none — still attaches, 60×/s at 60 fps |
| **physical read + own page walk (chosen)** | no driver change | **gdrv3: 9 GB swept, zero Javelin events** |

`ext/qk_va.py` = gdrv3 physical reads + `dumplive.Walk` page tables: **no `KeStackAttachProcess` at
all**. DTB + image base are cached per pid in `temp/qk_dtb_<pid>.txt` (first run of a session pays the
~70–80 s `p72_ppath.front_pid` scan; later runs are instant). Actions: `--pe`, `--at/--len` hexdump,
`--array/--slots` (decode the 44-slot candidate), `--watch=SECS` (the 1b gate).
`_ritual/qk1b_gate.ps1` runs the watch and **scores it against the Javelin log itself** — PASS requires
the read window clean *and* zero `EA Javelin Anticheat` 1000 events since t0.

apexdrv keeps its role as the *ship* transport: the same three primitives (DTB + physical read) can be
added to it later as a small, VM-benched change. That is deferred until 1b is green.



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
- **A raw physical read must be guarded by the RAM map interval set, never by `gio.is_ram()`.**
  `is_ram()` only rejects `>= ram_top` and the 640K–1M hole, so a qword pointing into an
  MMIO hole *below* 4 GB passes it, the read is issued, and the box **bugchecks**. Measured
  07/11 21:34: a hard reboot (no minidump written) during a window scan in `qk_va`, caused by
  trying every qword near a name hit as a CR3. Use `dl.usable_ranges()` and an interval test
  (`qk_va.Ram`), and prefer addresses derived from the object itself over guesses.

