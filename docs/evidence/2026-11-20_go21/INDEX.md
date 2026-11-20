# Evidence bundle — 2026-11-20 (go21 static-offset ESP chain)

Verbatim copies of this sitting's decisive artifacts; originals age out under `temp/`. Grading per repo law (R9): telemetry proves the PIPELINE, nothing here proves on-screen pixels.

| Claim | Receipt file | Decisive line(s) |
|---|---|---|
| PE header of located image matches the 9/11 build exactly | `r5_sizeofimage.txt` | `SizeOfImage=0xdfb8000 (223.7 MB)` |
| Located image fingerprint | `qk_offsets.txt` | `image_pa=0x48C6BD000` (13/11 exe, stamp `0x6AEBBC7D` — recorded in STATE 20/11) |
| Motion-free matrix election | `go21_elect_console.txt` | `RESULT: needle='Nessie' hits=9810 ents=68 (45.0s) pdelta=0xeec` · `RESULT: seeds=8 loosened=1297 total=1301` · `ELECT: rva=0x0daf8858 inliers=68/68` (first of TEN 68/68 rows; winner chosen as max-cluster front-runner, last line `VERDICT: FRONT-RUNNER`) |
| Runner / fallback candidate | `go21_elect_console.txt` | `ELECT: rva=0x0dc1b3b8 inliers=68/68` (second row) |
| Pair deployed to the lane | `qk_offsets.txt` | `vp_rva=0x0DAF8858` |
| Ring + matrix handshake live | `qk_go21_esp.txt` | `ring Local\qk_boxes mapped (6160 bytes)` · repeated `dbg it=N mat ok` / `feed ok geoms=207` · `vp from image_pa=0x48c6bd000 rva=0xdaf8858 : m15=4096.0000 m11=1.0000` |
| Census trajectory (contains a DEFECT, deliberately shown) | `qk_go21_esp.txt` | `frame 60 boxes=207` -> `frame 70 boxes=9715` -> `frame 130 boxes=18370` · `producer done, frames=181` · `exit=0` |

## What this bundle does NOT prove
- That any box sits on a visible entity — the eyes-on/camera-motion veto never ran (user moved to repo care before it could).
- That the elected VP is the LIVE camera matrix: `m15=4096.000 m11=1.000` constant across all 180 frames is equally consistent with a static shadow-cascade impostor.
- Names, health, teams, aiming: none bound in this lane; see FACTS 2026-11-20 section and PLAN 20/11 sections.
- Why the census blew up 207 -> 18,370 (later iterations raised box counts abruptly — filter over-loose; tightening is queued behind the veto).

## Reproduce (host, from repo root)
1. Detached shell per `_ritual/detach_run.ps1` doctrine; launch `temp/_go21_run.ps1` via
   `Start-Process -ArgumentList` using EMBEDDED quotes inside the element (spaced-path law, STATE 20/11).
2. Tail `temp/qk_go21_esp.txt`: expect `mat ok` / `feed ok geoms=` / `frame N boxes=...`.
3. Camera-motion veto (PLAN 20/11 19:3x): with the producer running and the game in lobby, rotate the
   view — boxes must translate with the camera, else flip `temp/qk_offsets.txt` to runner `0x0DC1B3B8`
   and repeat once.
