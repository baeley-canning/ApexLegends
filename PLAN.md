# PLAN — the only "what next" file

**Architecture (decided 2026-11-07 14:12, PHASE1 §11.6): A = external reads only.**
Nothing of ours is loaded or written into `r5apex_dx12`. No in-process DLL, no Present hook,
no manual map. Frozen branches are listed at the bottom and are NOT to be probed again until
the external MVP draws a box.

End goal: bnuuy-class external — **ESP, menu, aim** — then the write-path tier
(glow/no-recoil) and, separately, an economy research spike.

## The queue — strict order, one gate each

| # | Stage | Gate (the only thing that counts) | State |
|---|---|---|---|
| 0 | Reset the operating picture (this file, FACTS.md, offset table, host parked) | one page each, one offset table, host parked with a read-back | **DONE 07/11** |
| 1 | Live read bridge: `qk_probe` — BASE + READ8/READBUF on the game through `apexdrv` | MZ+PE at game base, **game alive at +60 s**, evidence file | in progress (self-mode PASS; needs a live pid) |
| 2 | Offsets + entity model, one authoritative header | firing-range dummy's hp/shield/team/position decoded **and** its projected screen coordinate lands on the dummy | not started |
| 3 | External overlay window (layered, click-through, topmost) | box on a dummy, camera-following | not started |
| 4 | Menu + config in that window | toggles change what stage 3 draws; config survives restart | not started |
| 5 | Aim (selection, humanisation, SendInput) | closet-settings session, no robotic tell | not started |
| 6 | bnuuy parity: skeleton, bars, names, distance, loot/deathbox, radar, patch-day offsets | full match, stable fps, offsets regenerated < 2 h after a patch | not started |
| 7a | Write path enabled (apexdrv WRITE): glow, no-recoil, no-spread | each VM-first, read-back, reversible | not started |
| 7b | Economy research spike (coins/packs) — **not a memory cheat** | 2 throwaway accounts, one repeatable dupe in ≤ 1 week, else park it | not started |

## Rules of engagement

1. One stage at a time. No probe that belongs to a later stage (R8 below).
2. A verdict that skipped the game half is **not** an in-game verdict (R9 below).
3. `qk_probe` output files, not chat text, are the state feed: `_ritual\qk_probe_*.txt`.
4. Driver/kernel work still goes VM-first (R1). `qk_probe` is **read-only** — no DSE write,
   no service start/stop, nothing to restore.
5. Every new run gets a new file. Never overwrite evidence (R5).

## FROZEN (do not re-probe; keep the evidence, stop the work)

- Remote-op injectors (VirtualAllocEx/CRT/RPM/WPM) — the jail, §11.1–11.7.
- `SetWindowsHookEx` loader (ov69–ov79) and the `C:\h330\ov76hook.c` line.
- Kernel manual map / ABI rungs h276–h286 (v13/v14 inject path).
- DSE windows, kdu provider ordering, VM benches (h310–h316) — until 7a.
- In-process Present/ResizeBuffers hook and the in-game menu.
- Physical band-scan as a *product* source (p62/p64) — kept only as a Stage-2 ground-truth oracle.

## Host state (read-only facts, 07/11 ~21:0x)

- `ApexDrv` (v14) and `gdrv3` are both `STATE 4 RUNNING` with no game process up.
  That is *not* parked: the next launch measures driver-resident. Stop both and read DSE
  back elevated **before** the next gate run.
- No minidumps in `C:\Windows\Minidump`. No reboot performed.
