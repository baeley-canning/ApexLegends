# LATEST_TRACKING — 09/11 18:57

## Live ESP verdict

**PASS.** `qk_live.py` drew 17 boxes over the live game for a full 10 s overlay run.

- Transport: **GIOV3 only** (`image_pa` static read + physical census records; no apexdrv, no DTB).
- Matrix: `image_pa=0x1F9B2B000`, `vp_rva=0xB88BCB0`, found by the h391 X/Y-forward `.data` scan.
- Check gate: 8/28 census records on screen, **17 boxes**, 77 reads, 0 refused, 0 failed.
- Overlay run: **10.0 s, 573 frames, 57.3 fps, boxes stayed at 17, reads=5586, refused=0, failed=0**.
- Game alive at the end: yes (pid 14008).

## Why this is not a false PASS

- h388/h390 proved the earlier qk_image candidates (`0x0DBB0F34`, `0x0DBB0E24`) put points on screen but used world Z as the forward axis, so +72 world “up” produced **0 boxes**.
- h391 therefore required the homogeneous row to be dominated by world X/Y, not Z, and only accepted candidates that produced boxes.
- `qk_live.py` now gates every 16-float window with `matrix_plausible()` before any projection, so torn or degenerate windows cannot be drawn as boxes.
- The final check and overlay run both read the same live matrix and census in one loop, and both ended with the game still alive.

## Evidence files

- `temp\_act_qk_image_live2.txt` — fresh qk_image `.data` scan (108 MB scanned, 8 raw candidates).
- `temp\_h388_out.txt` — candidate read-back; Z-forward candidates project but yield 0 boxes.
- `temp\_h389_out.txt` — column vs row and ±72 head diagnostic.
- `temp\_h390_out.txt` — matrix dump showing why the Z-forward candidates fail.
- `temp\_h391_out.txt` — X/Y-forward scan that found `vp_rva=0xB88BCB0` and cached `qk_offsets.txt`.
- `temp\qk_live_out.txt` — `--check` PASS and the 10 s overlay run.
