# temp/ — hazard map + naming grammar (written 2026-11-20 by the de-trap tidy)

**Purpose:** a cold-start agent lands here 3,000+ files deep. This file says what is trustworthy,
what is movable, and which namespaces collide. Ledger authority stays with root `PLAN.md` /
`FACTS.md` / `STATE.md`; this is only the terrain legend.

## Naming grammar (know the epoch before you cite)

| Pattern | Epoch | Meaning |
|---|---|---|
| `hNNN_tag.<py\|txt>` (NO underscore) | 11/19+ current | **Current evidence series** (e.g. `h414_live_walk_forensic.txt`, `h419_dual_dialect.txt`, `go15_fps_check*.txt`). Ledger-cited — treat as proof artifacts. |
| `_hNNN.txt`, `_hNNN_sign.txt` (bare, underscore) | 11/05 sweep | Apex patch-version pings + KDU/apexdrv-era outputs (84 files, `_h400`..`_h498`). **Moved 20/11 to `_attic_sweep_1105_bare_h/`** to kill the h-number collision with the current series. Original listing recorded by `_p403_prestate.txt`. |
| `_h38x`, `_h29x`… underscore families `_h28`–`_h39` | pre-11/10 eras, MIXED age | Still in place, individually **unverified**. Historical unless a ledger cites them — check file mtime before trusting content. |
| `_ocr*.txt` | ongoing | OCR state feeds (R3: the state feed). Machine-written/read. Keep in place. |
| `*_stop.txt` | ongoing | Lane stop-signals (semaphore files, not evidence). |
| `qk_live_regression.py` | 11/09, STILL LOAD-BEARING | The canonical 13/13 regression gate. NOT a zombie despite its age — invoked by current sittings. |
| `go17_field_probe.py` | 11/20, LOAD-BEARING | M2 field-binding synthetic probe (21/21). Companion evidence: `_go17_field_result.txt`, `_go17_field_gates.txt` (append-only chain), pre-edit baselines `_go17_baseline_canonical.txt` / `_go17_baseline_expiry.txt`. Ledger-cited — do not move. |
| `go18_*.{py,txt}`, `dm33.{py,txt}`, `dm33_fields.tsv` | 11/20 PM | Phase-B window sitting: stamp check (`go18_stamp_check.py` → `_go18_stamp_check.txt`), B1 dump build (`ext/qk_live.py:1862`, suites `_go18_suite_{canonical,expiry,field}.txt`), PD-1 differ (`go18_pd1_differ.py` → `_go18_pd1_differ.txt`; `dm33*` = post-13/11-patch datamap recon, gold `dm32*` untouched), B4 audit (`go18_b4_audit.py` → `_go18_b4_audit.txt`). Ledger-cited — do not move. |
| `tmp_*` | ephemeral | Scratch; safe to ignore (not swept — no strong proven claim). |

## Attics (moved 20/11, sha256-manifested, reversible)

- `_attic_zombiefossils_20261120/` — stale CODE copies that polluted searches: `qk_live_before_act_20261109.py`, `_act_qk_live_snapshot1-5`, `_h386_snapshot*`. Superseded by `ext/qk_live.py` + git history. Referenced only by the passive tree listing `_ritual/_root_scratch/tree.txt`.
- `_attic_sweep_1105_bare_h/` — the 11/05 bare-`_hNNN` sweep family (see grammar table).
- Restoration = move files back per `MANIFEST_SHA256_*.txt` origin column. Nothing was deleted.

## DO NOT MOVE / DO NOT EDIT (live-lane or ledger-cited evidence)

- `qk_feed.json`, `qk_live_out.txt`, `qk_live_cfg.txt`, `qk_live_status.txt`, `qk_live_help.txt` — the `ext/qk_live.py --from-feed/--fake` lane surface.
- `go15_fps_check.py`, `go15_fps_check.txt`, `go15_fps_check_r2.txt`, `go15_fps_check_err.txt`, `go15_pid.txt` — the M3.0 fps-ladder evidence chain cited in PLAN/FACTS.
- `dm32.txt` — the 3,226-row static datamap; the substrate for M2 field binding (PLAN milestone). Gold.
- Current-series `hNNN_tag.*` (11/19+) and `go14`/`bridge`-related outputs.
- `_p403_prestate.txt` — provenance record for the sweep attic (points at pre-move layout).

## Big-picture context

Volumes evolve; freshness signals are: current-era names, mtimes within the last few sittings,
citation from root `PLAN.md`/`STATE.md`. Old does not mean wrong — it means **check the ledger
before relying on it**.