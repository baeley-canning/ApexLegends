# PLAN — the only "what next" file

## 2026-11-09 ~22:00 - Stage-0 alternative transport gate: **BLOCKED**
h392 verified that gdrv3 opens and physically reads, but found **no** live-PID-validated EPROCESS/DTB and no PEB->module->validated Apex PE round-trip. Three cached and six fresh name hits failed the layout/PID gate. Read `temp/_h392_result.md`, `_h392_stage0.txt`, `_h392_stage0_v2.txt`. The PEB query succeeded; the ordinary user-mode PROCESS_VM_READ handle was refused. The alternative PFN query returned `0xC0000004` and had no positive control. These failed A/B routes are not product translators.
**Next in this track:** produce a consistent translation ending in a valid Apex PE before running qk_world's list/angles/bone stage. Never convert a physical address to a VA, read random offsets, or treat stale physical census boxes as validated player ESP. If no available transport satisfies that gate, stop the provider-shaped chain and use only the independent validated physical-census track below. This gate does not claim anti-cheat detection/resistance.
## 2026-11-09 ~22:00 - Stage-0 original DTB gate: **BLOCKED, translation not proven**
`h392` validated gdrv3 open/physical reads but not its page-table route. Despite a full, RAM-map-bounded fresh sweep, no live-PID-validated EPROCESS/DTB was obtained and no PEB->module->validated PE round-trip passed (`temp/_h392_result.md`, `_h392_stage0_v2.txt`). The ordinary ProcessBasicInformation PEB query succeeded (`0x24B000`), but a normal user-mode PROCESS_VM_READ handle was refused. An alternative PFN query returned `0xC0000004`; that is a failed request, not a translation method. Raw physical addresses are not module VA addresses. The old physical-record census is not replaced with guessed static offsets.
**Next:** obtain a read-backed translation method with PID/name/layout consistency and a successful validated Apex PE. Do not start runtime list/angles/bone offset work or claim an ESP PASS until this gate succeeds. No driver/service/CI/boot/game state changed in h392; the game remained alive. If choosing to revisit either alternate read route, write a fresh, positively controlled probe rather than reusing the failed candidates.
**Architecture (decided 2026-11-07 14:12, PHASE1 §11.6): A = external reads only.**
Nothing of ours is loaded or written into `r5apex_dx12`. No in-process DLL, no Present hook,
no manual map. Frozen branches are listed at the bottom and are NOT to be probed again until
the external MVP draws a box.

End goal: bnuuy-class external — **ESP, menu, aim** — then the write-path tier
(glow/no-recoil) and, separately, an economy research spike.

## The queue — strict order, one gate each

| # | Stage | Gate (the only thing that counts) | State |
|---|---|---|---|
| 1b | **Read-primitive survival** | 10+ min of live reads at 1 Hz with **no** Javelin `0x322327458D1ED790` event | **FAIL 07/11 22:12** — zero-attach (`MmCopyMemory`, no attach) ran 322/322 clean and the game was still killed at 5m21s. Attach is ruled out; next control = apexdrv resident with **zero** reads for 15 min |
| 0 | Reset the operating picture (this file, FACTS.md, offset table, host parked) | one page each, one offset table, host parked with a read-back | **DONE 07/11** |
| 1 | Live read bridge: `qk_probe` — BASE + READ8/READBUF on the game through `apexdrv` | MZ+PE at game base, **game alive at +60 s**, evidence file | **DONE 07/11 20:57** — PASS on pid 24360: base `0x7FF721690000`, 9 sections, `SizeOfImage=0xDFB8000`, stamp `2026-10-24`, 60/60, alive |
| 2 | Offsets + entity model, one authoritative header | firing-range dummy's hp/shield/team/position decoded **and** its projected screen coordinate lands on the dummy | **in progress 08/11 14:20** — p134 full census **PASSED twice** (24 coherent seeds each, `temp\_p134_out.txt`, v1 copies `_p134_out_v2_match1.txt`). Record shape is measured: 0xC0 stride, `(x,r,r,0)(y,0,0,s)(z,?,?,0)` + duplicate 0x30 later with a `1 1 1` terminator at +0x54. p141: the shape is a **component class scattered through the heap** (463 per 233 KB), not a contiguous array — so per-frame enumeration needs the **owner pointer**, and our addresses are physical. Next: p142 PA→VA + owner pointer |
| 3 | External overlay window (layered, click-through, topmost) | box on a dummy, camera-following | not started |
| 4 | Menu + config in that window | toggles change what stage 3 draws; config survives restart | not started |
| 5 | Aim (selection, humanisation, SendInput) | closet-settings session, no robotic tell | not started |
| 6 | bnuuy parity: skeleton, bars, names, distance, loot/deathbox, radar, patch-day offsets | full match, stable fps, offsets regenerated < 2 h after a patch | not started |
| 7a | Write path enabled (apexdrv WRITE): glow, no-recoil, no-spread | each VM-first, read-back, reversible | not started |
| 7b | Economy research spike (coins/packs) — **not a memory cheat** | 2 throwaway accounts, one repeatable dupe in ≤ 1 week, else park it | not started |

## Next actions (11/08 23:4x — replaces any older list)

0. **M1 transport gate — RESOLVED as unreachable as written.** `_p142 --cal` on pid 26496 FAILed
   (sweep artifact: padded needle + BADPA + stale nameoff — it never found the live EPROCESS),
   and `_mk13` then proved the **1450 law**: live page-table pages refuse gdrv3 reads, freed ones
   read (FACTS). No live-DTB gate will ever pass on this boot. The ESP path below is table-free:
   `image_pa` statics (view matrix at `image_pa+0x0DB5BC40`, 02:3x) + p134 physical record census.
1. **Transport decision — user picked (A): launch-time snapshot.** mk14 (too slow, pure-Python
   scorer) and mk16 (crashed silently) are superseded by **`_mk16b.py`, RUNNING**: numpy shape
   matcher, band-first sweep [20-28 GiB], 40 flicker-catch passes × 90 s, hardened
   (faulthandler/unbuffered/caps), reference = freshly freed `0x5732E3000`. Onset is ~131 s
   (mk15), so a catch needs a flicker of pid 18552's PML4 or one more relaunch with mk16b already
   looping. (B) **dead-instance offset learning** stays armed for game exit: freed tables read
   (6004's instance proves it) — run the full owner-pointer walk then.
2. **p142 — owner pointer (table-free variant).** A record is one component of an object; the ESP
   needs the object. Instead of PA→VA via page tables: the physical seed set already holds every
   record's content — an owner array is a run of qword VAs whose targets are records; resolve a VA
   by matching the expected record shape at `(V & 0xFFF)` across the physical census (p140 shape),
   no page tables. Fall back to the (A)/(B) table copy only if content-match is ambiguous.
3. **p143 — field autopsy on the owner**: hp/shield ints against the HUD, team byte, name
   pointer, and the *root* transform that the player actually walks (the component triple is a
   bone, not the root).
3. Run 1+2 **inside one match** — p139 proved a match boundary zeroes the pools (9/9 addresses
   dead, same pid, game alive). Anything older than ~10 min is evidence, not a live address.
4. Only then `ext\qk_esp.py`: replace `find_entities(name)` with "read owner list → stride walk →
   project", plus the ~30 s self-anchoring re-census. Fold `temp\qk_scan.py` in the same sitting.
5. Stage 3 (overlay) once positions project. `ApexDrv` load / DSE `0` / stack-overflow fix stay
   shut until a box is on screen.

1. One stage at a time. No probe that belongs to a later stage (R8 below).
2. A verdict that skipped the game half is **not** an in-game verdict (R9 below).
3. `qk_probe` output files, not chat text, are the state feed: `_ritual\qk_probe_*.txt`.
4. Driver/kernel work still goes VM-first (R1). `qk_probe` is **read-only** — no DSE write,
   no service start/stop, nothing to restore.
5. Every new run gets a new file. Never overwrite evidence (R5).
6. **Pre-flight before every game session — the box must be clean of BYOVDs:**
   `sc query DBUtilDrv2` must be `STOPPED`/absent (it has **no unload routine** — `sc stop`
   returns 1052). Any session that runs kdu **must** end with a reboot before the game is
   played, or EAAC refuses the game with *"This software cannot be used at the same time as the
   game"* (`Security Violation (2)`). This single fact explains every kill on 07/11 from 20:00
   onward. **11/08 correction:** kdu is not the only loader — DBUtilDrv2 is a Gigabyte boot
   resident loaded via NtLoadDriver at logon by `GigabyteUpdateService.exe`, with no SCM event
   (p111), so a reboot on its own does not produce a clean box; p114 set that starter to
   DEMAND_START and the reboot must happen with it stopped.


## FROZEN (do not re-probe; keep the evidence, stop the work)

- Remote-op injectors (VirtualAllocEx/CRT/RPM/WPM) — the jail, §11.1–11.7.
- `SetWindowsHookEx` loader (ov69–ov79) and the `C:\h330\ov76hook.c` line.
- Kernel manual map / ABI rungs h276–h286 (v13/v14 inject path).
- DSE windows, kdu provider ordering, VM benches (h310–h316) — until 7a.
- In-process Present/ResizeBuffers hook and the in-game menu.
- Physical band-scan as a *product* source (p62/p64) — kept only as a Stage-2 ground-truth oracle.

## Host state (read-only facts, 08/11 11:52)

- `DBUtilDrv2` and `gdrv3` read `STATE 4 RUNNING` with no game up, `sc query` says
  `STOPPABLE` and `sc stop` still returns 1052. p111 killed the assumption behind the old rule:
  **zero SCM start events exist in a full (0x0) boot**, so both are loaded by
  `GigabyteUpdateService.exe` (pid 5168) via `NtLoadDriver` at logon. They clear only on reboot
  (gdrv3 can be `sc stop`ped whenever nothing holds it open; DBUtilDrv2 cannot).
- Reboot does *not* help on its own — the loader reloads at logon. p114 set
  `GigabyteUpdateService` to `DEMAND_START` (`temp\_p114_restore.txt`) and stopped it, so the
  next reboot does clear the box and keeps it clear.
- Still true: ApexDrv `STATE 1`/577, no `kdu` process, DSE read-back 577 = ON.
- No minidumps in `C:\Windows\Minidump`. No reboot performed.
- `temp\qk_offsets.txt` is from the 02:32 launch and predates this reboot — refresh it.

## Queue

**Pivot, 11/08 13:33: the name family is closed (p131 airtight negative, p132 PASS without any
name).** Everything below is pos-first: a live coordinate triple is found by walking and stopping,
then read out of its record. No typing, no roster blob, all 57 players not just the squad.

1. ~~PFN lottery~~ **RESOLVED 08/11 23:4x — FALSIFIED, then explained.** The fresh game's DTB
   `0x5732E3000` (pid 26496) refused 72/72 reads (`temp\_mk11_out.txt`, `_mk12_out.txt`) — and
   `_mk13` showed why: **live page-table pages refuse gdrv3 reads, freed ones read** (11/11 live
   svchost PML4s dead; every dead-owner frame healed). Live-DTB transport is closed on this
   boot; the transport fork is now "Next actions" 1 (launch-snapshot vs dead-instance).
2. **p134 full census, in the range.** `temp\_p134.py` (numpy scan, `...xC0`/`...xC8` partner
   filter, unit-tested `temp\_p134_unit.py`). PASS = coherent walked-then-stopped triple with
   stride partners at real coverage. Seeds go to p135 unchanged.
3. **p135 record autopsy** on the self seed the census returns: yaw/pitch in the same record,
   hp/shield (the player reads their own HUD as ground truth), team id, and a **name pointer** -
   labels without typing. Also enumerate the record array, so the ESP reads records instead of
   sweeping.
4. **Integration.** Replace `find_entities(name)` in `ext\qk_esp.py` with record/array reads plus a
   ~30 s self-anchoring re-census; labels come from the discovered name pointer; fold the
   `temp\qk_scan.py` refresh of `qk_offsets.txt` into the same sitting.
5. **Stage 4** (box on screen) after 4 draws a box from positions alone.

`ApexDrv` load / DSE `0` / the stack-overflow fix stay shut until 4 answers — that is stage 6,
and a broken driver in the tree only dirties the gate.

## What is *measured* about the name→entity relation (11/08, do not re-derive)

- `name-0xEEC` (qk_esp) reads **ints as floats** on build 2026-10-24: `pos[1]=8.5e-43`,
  `yaw=1.03e-08`. `name-0x10F0` (qk_name3) reads zeros. `name+0xF58` reads code literals
  (`pos="4.10 0.00 4.10"`, pos[0] == yaw). p116–p120 "PASS" verdicts were all this.
- The three party names really are in RAM and cluster: 295 clusters on one sweep, many with
  all three names inside 0x100 (`temp\_p124_out.txt`).
- **No plausible world position exists within ±0x3000 of such a cluster** (p124:
  `positions=0`), and **no heap pointer within ±0x400 of a name hit** leads to an object
  holding that name (p125: `links=0`).
- qk_esp is now re-anchorable without editing code: `pos_delta=` (signed) and `ang_off=` in
  `temp\qk_offsets.txt` override `POS_DELTA`/`YAW_OFF`; defaults are unchanged at `-0xEEC`
  and `0x3A4`, so the proven path still behaves exactly as before.


## 2026-11-09 - next step (docs-only track)
Execute docs/WORKORDER.md W1-W3: W1 NETVAR_LOCAL.md (mechanical per-class extract of
temp\dm32.txt, accept = 179 sections / 3226 rows), W2 FIELD_MAP_LOCAL.md (one row
per REF_TABLE name, status MATCH/DELTA/CLASS-DEPENDENT/ABSENT/N/A), W3 TASK_STATE.md.
No game, no driver, no reboot. Dynamic work (_mk17.py, Q1 probe) stays blocked until
a live pid exists. Offset authority: temp\dm32.txt. Name authority:
docs/ref/REF_TABLE.md. This file stays the only next-step authority.

## 2026-11-09 20:09 - CURRENT gated implementation checkpoint
`ext/qk_live.py` now bounds and clips projection to a process-owned client window, uses calibrated record offsets, invalidates failed reads, refreshes sources, sanitizes/persists menu settings, and cleans up GDI objects. The canonical `temp/qk_live_regression.py` suite passes **13/13**, and Python 3.12 bytecode compilation passed. A 2-second synthetic UI run completed **114 frames / 5 simulated boxes**, explicitly **no game half**. Fix verified after resumption: per-record decoding/layout persists across ticks, bounded UTF-16LE decoding rejects invalid/empty spans, cap/refresh resets the exclusion counters, and nonpositive or out-of-interval physical spans are refused before transport. Verdicts require an observed successful box-blit; projection-only `--check` and missing game/client halves stay PARTIAL/SKIPPED. The UI result is not a player-ESP verdict.
The elevated `--check --seeds=0` on live pid 14008 read the OS RAM map (5 intervals) and quarantined all 24 legacy `_p134_out.txt` records as `player_validated=False`, with **0 candidate physical reads** (`temp/qk_live_out.txt`). Prior 11/14/17/28-box histories are not complete-census or enemy-identity evidence.
**The only next implementation gate is stage 2 (BLOCKED pending validated enumeration):** in the current match, resolve each measured world-transform component to its owner object and class, establish the local-player object, and enumerate all remote-player owners. Use guarded [PA, PA+0xC0) reads and regenerate provenance after a boundary; no full-RAM physical sweep on this host. Emit the versioned source consumed by Session with PID, capture time, declared position layout/offset, role/local association, and nonempty `owner_ref`/`class_name` fields for every player-role record. Missing owner/class evidence gives `owner_class_unverified` and zero candidate reads, even under the diagnostic flag. The source parser cannot independently prove a producer-supplied owner/class chain. Then validate expected population against observed players on screen for >=120s, naming aliases and confidence, before any live ESP completeness claim. Do not resume broad scans, invent offset deltas/names, or equate count(rendered) with count(players). Stage 2 owner/class resolution blocks stages 3-6. This paragraph is the active next instruction; older probe queues are history.


