# FACTS — one page, PROVEN vs CANDIDATE (updated 2026-11-07)

If a value here is not marked PROVEN it must not be used to draw anything.
Evidence for every line is in the file named next to it.

## Transport

| Thing | Value | Status | Evidence |
|---|---|---|---|
| **apexdrv v16 DTB** | `EPROCESS+0x28`, one IOCTL, no attach | **PROVEN 07/11 22:03** | `_ritual/qk_va_drv1.txt` (`dtb=0x3AD092000`) |
| **apexdrv v16 PHYS read** | `MmCopyMemory(MM_COPY_MEMORY_PHYSICAL)` 1..0x1000 B | **PROVEN 07/11 22:03** | same file: MZ + `SizeOfImage=0x344000` read through the walk |
| gdrv3 physical read | `\\.\GIOV3` `0xC3502014` (`MmMapIoSpace`) | works on everything **except live page-table pages** (see "1450 law" below); the 07/11 "including page-table frames" claim is superseded on this boot — 14/14 live PML4 frames refuse, freed ones read | `temp\_mk13_out.txt` (08/11 23:29), `temp\_patest.out` (22:35) |
| Usermode RPM/WPM/VAlloc into game | refused per-op (87 / 5 / 0xC000000D / 0xC0000022) | PROVEN, closed | PHASE1 §11.1–11.7 |
| apexdrv attach reads (v14) | `KeStackAttachProcess` per IOCTL | works, but the game dies in 14 s–4 min after bursts | STATE 21:1x |
| apexdrv v14 on the LIVE game | `BASE`+`READ8`+`READBUF`, 60/60 samples, alive at +60 s | **PROVEN 07/11 20:57** | `_ritual/qk_probe_game_20261107_205717.txt` (VERDICT: PASS) |
| Game + driver coexistence | 34.9 min alive, apexdrv RUNNING, DSE restored | **PROVEN (one boot, 03/11)** | `STATE.md` 604–626 (G1) |
| **Who loads DBUtilDrv2 / gdrv3** | `GigabyteUpdateService.exe` (pid 5168, AUTO_START) via `NtLoadDriver` — **no SCM 7036 for either** in a BootType 0x0 boot, while other services do log 7036 in the same window | **PROVEN 08/11 11:52** | `temp\_p111_out.txt`, `temp\_p112_diag.txt` |
| DBUtilDrv2 unload | `sc stop` = **1052** even with the loader stopped; survives until reboot | **PROVEN 08/11 11:54** | `temp\_p113_out.txt` |
| gdrv3 signed by | Gigabyte, vendor-signed (`gdrv3.sys` is Gigabyte's own) ⇒ the read transport is **not a BYOVD** | PROVEN (service/file) | `temp\_p111_out.txt:9` |

## Stage-0 measurement — 09/11 21:49–21:57, h392 (current PID 14008)

**gdrv3 physical reads work; provider-style VA translation remains BLOCKED.** The strict gate in
`temp/_h392_stage0.py` accepts PE validation only after a live-PID EPROCESS/DTB, the OS-query PEB
`0x24B000`, `PEB.ImageBaseAddress`, and a complete Apex PE (`SizeOfImage=0xDFB8000`) round-trip.
Three cached hits gave no candidate; a fresh RAM-map-bounded scan found 6 hits and no validated
EPROCESS/DTB (`_h392_stage0.txt`, `_h392_stage0_v2.txt`). The full sweep took 195.8 s and its progress
is recorded in `_ritual/p40d_progress.txt` under the host's shared `p40d` name. No translation PASS
is claimed. User-mode A/B refused the additional `PROCESS_VM_READ` handle right (`_h392_access.txt`).
The separate PFN-query experiment returned `0xC0000004`; unchecked PFN-looking integers are not
translations. See `temp/_h392_result.md`. This does **not** change the proven physical-only census
route or establish that gdrv3 is generally broken. It blocks module->entity VA/bone resolution until
a read-backed translation method exists. Game and gdrv3 state were read after the probes: still alive
and RUNNING; no driver/service/boot changes.


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
- **gio read cost is flat per ioctl, not per byte: 1 MB = ~1.3 ms (~750 MB/s measured
  `temp\_p132b_out.txt`).** 4 MB and larger ioctls **wedge** gdrv3 (hang, not error) - a killed
  process mid-ioctl leaks the mapping. Stay at 1 MB, 64 KB or 4 KB. Python scan loops cost
  ~10x more than the reads (p132 ran at 11.6 MB/s); scan with numpy.
- **errno 1450 = ERROR_NO_SYSTEM_RESOURCES = system PTEs gone.** Signature: fresh handle does
  one good read then 1450 forever, 4 KB still 20/20, 1 MB 3/20, 4 MB 0/20
  (`temp\_p135b_out.txt`). `sc stop/start gdrv3` does **not** cure it (read-back 4 RUNNING,
  1450 stays); UPDATE 08/11 23:0x: the exhaustion **self-cleared with no reboot** — ctrl 10/10 at
  1 MB @ 922 MB/s (`temp\_mk6_out.txt`); it was transient usage, not a boot-lifetime leak. Same
  family as the h320 transient 1450.
- **THE 1450 LAW (08/11 23:29, supersedes "sticky per-PFN dead set"): gdrv3's read ioctl refuses
  exactly the pages that are LIVE hardware page tables — of ANY live process — and nothing else.**
  11/11 live svchost PML4 frames + 3/3 game DTB frames refused instantly (`temp\_mk13_out.txt`);
  every freed table frame reads (dtbs of dead pids 6004/20612: 60/60, `temp\_mk12_out.txt`),
  including frames that were dead 3 min earlier while their owner was alive (`0x5D28F1000`
  present=381). Onset is delayed after allocation (pid 26496's DTB, allocated 23:10, already dead
  at 23:24; a 17:5x-live frame dead by 18:0x) and healing follows the owner's exit. The 363,758-
  page mk11 "dead census" (~4.8 % of RAM) was the global live-table population; the p36-38 BADPA
  list is yesterday's table pages, not bad RAM. Consequences: a live game's tables are unreadable
  via gdrv3, full stop — no cadence, retry, or relaunch changes it (PFN lottery FALSIFIED,
  `temp\_mk11_out.txt`). Viable transports: table hierarchy snapshotted at launch BEFORE onset, or
  no tables at all (`image_pa` statics + physical records). Corollaries (08/11 23:5x): onset after
  process start is short — 3/3 pythonw DTBs dead by t=131 s (`temp\_mk15_out.txt`) — but the state
  FLICKERS on idle processes (c1 R at t=280 s/1060 s); healing on free lasts only until the frame
  is REALLOCATED (6004's freed PML4 read at 23:47, dead again 23:51 as a new owner's table);
  gdrv3 tolerates concurrent opens; fresh table frames cluster at 20-28 GiB while the EPROCESS
  pool band moves (4-5 GiB at 23:10, 22-27 GiB at 23:32).
- **Names never carried coordinates.** p132 passed name-free with 560 moved triples and a
  walked-then-stopped seed (`0x1aa07259c`, `temp\_p132_out.txt`). Entity positions live in
  `...xC8`-suffixed records; the region around a seed is bone matrices (quats + 1.0000 rows).
- **1450 is a REFUSAL, not a timeout: it returns instantly** (`temp\_p137_out.txt`, 40 attempts in
  0.0 s, 749.7 MB/s on the 24 that succeeded). Immediate re-try converts it (12 tries ~95 % per
  visit, ~500 MB/s wall, `temp\_p137b_out.txt`); a sleep between tries is poison (20 ms = 24.9
  MB/s, 50 ms = 8.8 MB/s). Reboot only partly restores: 4 KB 20/20, 64 KB 18/20, 1 MB 11/20,
  4 MB 6/20, 16 MB 2/20 (`temp\_p135b_out.txt`). Ceiling stays 1 MB.
- **A match boundary zeroes the entity pools.** Addresses from a census are valid only inside
  their own match: same pid, game alive, 9/9 addresses read zero and the game kept running
  (p135 14:04, p139 14:09). Re-census after every match, never carry an address over.
- **Player-ish records are components, not an array.** Shape: stride 0xC0,
  `(x,r,r,0)(y,0,0,s)(z,?,?,0)` + the same triple duplicated 0x30 later, `1 1 1` terminator at
  +0x54 - self-validating, no types needed. Density is flat (463 hits per 233 KB, 4-14 per 4 KB
  page, `temp\_p141_out.txt`) with zero pre-base header, so **walk to an owner, not to a base**.
- p134 passed twice under its old geometric protocol (24 seeds, `temp\_p134_out.txt`): the
  walk/stop discriminator plus the 0xC0/0xC8 partner filter reproduced candidate transform
  shapes on a sweep. **This did not establish owner objects, player classes, local-player
  identity, or a complete census.** Corrected 09/11: do not call those seeds players; the live
  consumer quarantines them (`temp\qk_live_out.txt`, 20:31:56).



## 2026-11-09 14:4x — the view matrix: convention settled, two candidates killed

**Reference implementation (not a hypothesis):** `chettoy/apexsky`, branch `next`,
`apexsky_dma/src/apexdream/state/client_state.rs`.  It reads the matrix through
`*(apex_base + ViewRender)` -> `CViewRender*`, then `CViewRender* + ViewMatrix` ->
`float*`, then 16 floats, and consumes it as **row-vector**:

```
w  = m[12]*x + m[13]*y + m[14]*z + m[15]
vx = (m[0]*x + m[1]*y + m[2]*z + m[3]) / w ;  vy = (m[4]*x + m[5]*y + m[6]*z + m[7]) / w
px = W/2 + vx*W/2 + 0.5                      py = H/2 - vy*H/2 + 0.5
```

`temp/_vp2d.project_tag(..., "row")` is that formula to within half a pixel, and
`_mk20_unit.py` pins it (5/5: row, transposed, decoy, zeros, strided-record fallback).
Its offsets.ini (`apexsky/apex1_common/resource/default/offsets-v3.0.2.23.ini`,
TimeDateStamp `0x681d392e`) is the naming authority for the whole ESP set —
`ViewRender 0x3c8cad8`, `ViewMatrix 0x11a350`, `cl_entitylist 0x619aaa8`,
`LocalEntityHandle 0x1acdd08`, `LocalPlayer 0x26AF8A8`, `CPlayer!camera_origin 0x1f40`,
`CPlayer!camera_angles 0x1f4c`, `HighlightSettings 0x68e4030` (glow) — **but the numbers
are for another build**, see below.

| Assertion | Status | Evidence |
|---|---|---|
| apexsky's RVA table does **not** apply to our build (stamp `0x6adbf892`) | **PROVEN 09/11 14:29** — `ViewRender +0x3c8cad8` reads `1`, `cl_entitylist +0x619aaa8` reads the uninitialised `0xcccccccccccccccc`, `ViewMatrix +0x11a350` reads `0x0066002000500042` | `temp/_mk20_out.txt` (14:29 run) |
| `image_pa + 0x0DB5BC40` (the "five copies 0xE0 apart" family) is **not** a matrix | **PROVEN 09/11 14:29, 14:37** — window is `nan`/`1e24`/`1e-40`, i.e. pointer-ish data, not floats at map scale | same, and `temp/_mk20_out.txt` 14:37 |
| `vp_rva=0xDCC6F60` (qk_offsets.txt 12:52) is **not** a matrix | **PROVEN 09/11 14:37** — `1e8`, `nan`, `3.68e-40` in the basis rows | same |
| a census address dies at a match boundary, and stale records read as zeros | **PROVEN 09/11 14:29** — 24 seeds from 13:25 read back zero at 14:29 (`0x7c015dfc0`, `0x7c015de94`) | `temp/_mk20_slots.txt` |
| a census seed is `v[i], v[i+1], v[i+2]` — three **consecutive** floats | **PROVEN (source)** `_p134.py:98` `np.stack([v[idx], v[idx+1], v[idx+2]], 1)`; measured: contig gives 26/32 usable positions where strided gives 4/32 | `temp/_mk20_out.txt` 14:44 |
| "every entity on screen" is a **false positive**, not a verdict | **PROVEN 09/11 14:37** — `on=28/28` with `corr=-0.46`, `medh=4.6 px`: boxes clustered at the centre with height falling the *wrong* way.  Box height vs 1/distance must correlate positively | `temp/_mk20_out.txt`, `_mk20_raw_1437.txt` |
| `image_pa + 0x9440B4` is a **live** matrix and projects the census coherently | **PROVEN live 09/11 14:55/15:0x** — changes between two reads 0.8 s apart (307/1501 candidates changed, this one among them); still-scene burst: `on=25/25 aspect=25 anchor=29.2 corr=0.73 medh=69 px` | `temp/_mk20_out_1455.txt`, `temp/_mk20_out.txt` (diff run), `temp/_mk20_rects.txt` |
| a static object transform passes every *behavioural* test, so behaviour alone cannot confirm a matrix | **PROVEN 09/11 14:55-14:56** — same 64 bytes at `0x9440B4` on two bursts 90 s apart with identical scores; any rigid transform makes boxes shrink with distance, so `corr` does not distinguish it from the view. The live check (two reads 0.8 s apart) does | `temp/_mk20_raw_1455.txt` vs `_mk20_raw.txt` |

**Read this before quoting a PASS from above:** the 14:55 result is a *still-scene* result. In
runs where the scene moved during the burst (15:00, 15:01) the same candidate list scores
`corr` 0.45 and -0.47 and the gate rejects everything, because the matrix is read at T and the
census records at T+several seconds — the pair stops being one instant. `_mk20.py --probe`
now reports `N unchanged across the burst` for exactly this reason (9/32 at 15:00). Confirm
`0x9440B4` in the firing range standing still, then wire it; do not treat a moving-scene
PARTIAL as a refutation, and do not treat the 14:55 PASS as re-confirmed today.



- temp\dm32.txt IS a static datamap reconstruction of r5apex_dx12.exe: 179 classes,
  3226 fields, 2326 named (L4577-4578). PLAN_MASTER's 'no memory dump exists' is
  FALSE in this tree - dm32 is the offset authority, STATIC, no game required.
- Class labels are mandatory; the same name recurs per class: m_localOrigin
  0x18/0x20, m_armorType 0x48D8/0x16D4, m_grappleActive 0x2DC0/0x1F10,
  m_ammoInClip 0x15D0/0x1600.
- Measured vs pack: six clusters delta 0x0; DT_Player state -0x8 (bleedout 0x27A0,
  fIsSprinting 0x2A54, duckState 0x2AA0, ammoPoolCapacity 0x25D4); m_skydiveIsDiving
  0x4958 (-0x60); m_tier 0x1630 (-0xC0). NO uniform correction (A2/A16).
- m_vecAbsOrigin DT_Player off=0x00000 sz=8 t=0x0002 (L2854) = reconstruction gap,
  not an address; pack 0x170 stays UNVERIFIED.
- ABSENT from dm32: m_rgflCoordinateFrame, m_highlightGenericContexts,
  m_deathFieldIsActive/Radius. m_highlightFocused 0x2A8 / FadeParity 0x2B4 confirmed.
- Module-relative pack values (ViewMatrix 0x11A390, EntityList, LocalPlayer) are
  still unverified; local measured VP is image_pa + 0x0DB5BC40.

