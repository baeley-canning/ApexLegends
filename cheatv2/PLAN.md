# PLAN.md — cheatv2 / external overlay for r5apex_dx12.exe

## HARD RULE — VM for anything that can crash
- **ALL** physical memory work (Steps 02-06) MUST run in the VM first. Host = last step.
- **ALL** elevated runs (any `runas`, `ShellExecuteW("runas")`, admin prompt) MUST run in the VM first.
- **ALL** driver load/unload, device open, IOCTL calls, page mappings — VM first.
- If the VM cannot start, say so and stop. Do NOT "just try it on the host."
- If you are unsure whether something can crash the host, **assume it can** and use the VM.
- **CRASH LOG**: Every elevated run on the host writes a crash log to `cheatv2/CRASH_<YYYYMMDD_HHMMSS>.log` with: the command run, exit code, stdout/stderr, and a timestamp. This lets us see what killed the host.

## Phase Map
- Phase 1 (steps 01-03): primitive proven — game closed
- Phase 2 (steps 04-06): kernel access — game closed
- Phase 3 (steps 07-10): game data — game running
- Phase 4 (steps 11-13): ESP — game running
- Phase 5 (steps 14-15): aimbot + polish — game running

## Steps

### 01 Device open
- [x] Phase 1 code implements auto-detect: tries Copy mode (0xC3502004) first, falls back to Map mode (0xC3502808/0xC3502804).
- [x] Prints mode detected (Copy or Map).
- [x] **Acceptance test:** Prints "device open, mode = Copy" or "device open, mode = Map".

### 02 Physical read smoke test
- [x] Phase 1 code reads 0x1000 and 0x100000 (32 bytes each), prints hex.
- [x] Checks for uniform fill (all 0x00 or all 0xFF) and warns.
- [ ] **Acceptance test:** Both reads return success, bytes differ between addresses, at least one buffer contains non-uniform data.

### 03 Physical write smoke test
- [ ] Read a byte at a known physical address, flip it, write it back, read it back.
- [ ] Confirm the byte reverted correctly.
- **Acceptance test:** Console prints "WRITE PASS" after round-trip.

### 04 Kernel base discovery via the gdrv path
- [ ] Walk PML4[0] of a known-good CR3 or use the VA->PA translation to find the kernel NT header.
- [ ] Print the base and the DOS/NT header magic as proof.
- **Acceptance test:** Console prints "KERNEL BASE = <addr>" with MZ/PE signature verified.

### 05 EPROCESS walk from PsInitialSystemProcess
- [ ] Enumerate ActiveProcessLinks from System, find PID of r5apex_dx12.exe.
- [ ] Print CR3 / DirectoryTableBase for the target PID.
- **Acceptance test:** Console prints "EPID = <pid>, CR3 = <addr>", matches OpenProcess PID.

### 06 VA->PA translation: 4-level page walk
- [ ] Implement PML4/PDPT/PD/PT page walk with 1GB and 2MB large-page cases.
- [ ] Read the target's PE header in its own VA space and verify the MZ/PE signature.
- **Acceptance test:** Console prints "PE VERIFY OK" for the game module base.

### 07 Overlay window
- [ ] Create a transparent, topmost, click-through window.
- [ ] Render an ImGui frame with a counter (e.g. frame count).
- [ ] Confirm the game stays focusable and the overlay is invisible to clicks.
- **Acceptance test:** Overlay appears on screen; clicking through it hits the game.

### 08 Module base for the game module, then read the view matrix and print it
- [ ] Find the game module base via physical memory (MZ/PE scan in process VA space).
- [ ] Read the view matrix at the known offset and print it.
- **Acceptance test:** Console prints "MODULE BASE = <addr>" and a 4x4 view matrix with reasonable float values.

### 09 World-to-screen
- [ ] Implement world-to-screen projection using the view matrix.
- [ ] Print screen coords for a fixed world point and check they move correctly when the camera does.
- **Acceptance test:** Moving the camera in-game causes the projected point to move on-screen as expected.

### 10 Entity iteration
- [ ] Read the entity list from the game (via known offset or scan).
- [ ] Print entity count and the first 10 entity addresses.
- **Acceptance test:** Console prints "ENTITY COUNT = N" and N entity addresses.

### 11 Names and distance
- [ ] Read signifier name from each entity and compute distance from local player.
- [ ] Render text above one entity.
- **Acceptance test:** Names and distances appear in the overlay for nearby entities.

### 12 Box + skeleton ESP
- [ ] Render 2D boxes around projected entity positions.
- [ ] Draw skeleton lines between bone positions.
- **Acceptance test:** Boxes and skeletons appear around entities in-game.

### 13 Glow write behind a config flag; overlay-halo fallback if it fails
- [ ] Write the native glow/highlight bits via physical memory write.
- [ ] Keep an overlay-drawn halo behind a config flag as fallback.
- **Acceptance test:** Entities glow in-game (native) or show overlay halos (fallback).

### 14 Aimbot: bone read, angle math, smoothing, hotkey
- [ ] Read bone matrix for nearest-bone target selection.
- [ ] Implement angle math with smoothing and a hotkey.
- [ ] Use SendInput for mouse movement.
- **Acceptance test:** Holding hotkey moves crosshair toward nearest entity.

### 15 Config file, hotkey table, and a clean shutdown path
- [ ] Load/save config from a JSON/INI file.
- [ ] Define hotkey table.
- [ ] Implement clean shutdown (close device handle, release mappings).
- **Acceptance test:** Config loads correctly; overlay closes cleanly on exit.

## Offset Policy (from original)
- The view matrix and entity list are the two that matter; everything else hangs off them.
- Names, glow bits and bone indices are [UNVERIFIED] until dumped.
- Print every offset read from, with its value, in the step that first uses it.

## Stop And Ask If
- The device opens but every IOCTL returns an error.
- The game is not running when a step needs it.
- Two consecutive build failures on the same file.
- A step needs an offset that is not in VERIFY.md and you cannot derive it.
