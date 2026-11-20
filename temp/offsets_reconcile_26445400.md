# offsets_reconcile_26445400.md — candidate offset sets vs live build (2026-11-19 22:4x)

## Live-build pin (disk truth, no game process involved)
- EXE: `C:\Program Files\EA Games\Apex\r5apex_dx12.exe`
- FileVersion=1.0.0.0 (generic, meaningless) · **LastWriteTime=2026-11-13**
- ⇒ live client = the **Nov-13 patch**, matching CheatOffsets pinned **build 26445400**
  (their dump updated 2026-11-13 22:45 UTC). Process-module versioning was attempted first;
  Javelin blanks remote module views (PID 25548 `Path`="" `MainModule` null) — side-QK datum.
- Consequence: FACTS.md's verdict stands doubled — the generated.h table was measured Nov 7
  against the **Oct-24 build**; the client patched Nov 13. Everything pre-Nov-13 is doubly stale.

## Candidate sets on the table (status legend: ✅ live-proved · ⚠️ plausible · ❌ proved wrong · 🪦 obsolete)

| Field | Set A gen.h (Oct-24) | Measured 07/11 | Set B qk_va live cand. | Set C Sato repo | Set D comm. 26445400 | Set E historical-self |
|---|---|---|---|---|---|---|
| ENTITY_LIST | 0x23F6A90 | ❌ 0x5E2C1480475A9C4 / unmapped ±0x1000 | scored via decode() tonight | 0x19224d8 🪦 | 0x19126a8 🪦 **(2021-10)** | — |
| VIEW_MATRIX (B/A) | 0x1B4DFA0 / 0x022EE01 | ❌ 2.9e23 / code | — | 0x1b3bd0 🪦 | 0x1cef8d0 🪦 **(2021-10, absolute-static — NOT ViewRender-chained; scheme differs from both B and C)** | vp_rva 0xDD792B0 (Aug-11 --data --watch; predates viewer refactor) |
| LOCAL_PLAYER | 0x01E7D4B8 | ⚠️ untested | — | 0x1cd1d58 🪦 | 0x1cc1f48 🪦 **(2021-10)** | — |
| origin/hp/shield/team/name | sets untested | no ents reachable | ENT_FIELDS + ENT_TAIL (team 0x10E8, namePtr 0x10F0 rel 0x10D8 block; shield 0x5E8 …) | 0x14C/0x438/0x170/0x448/0x589 🪦 | netvars 🪦 **(2021-10)**: shield 0x170/max 0x174 · team 0x448 · visFlags 0x440 · spotted 0x948 · signifier 0x580 · iName 0x589 · glow En/Typ/Col 0x3C8/0x2C0/0x1D0 · LastVisTime 0x1ACC | — |
| NameList | — | — | — | 0x84056a0 🪦 | 0x83836d0 🪦 **(2021-10; note C/D agree ≈0x83-84 region — C-vs-D cross-datum, both dead eras)** | — |
| ENTRY stride | 0x6758 (KB) | — | — | NUM_ENT_ENTRIES 0x10000 | not published in dhanax26 Offsets Dump.txt (only interfaces/classes/globals+glow) | — |

## Forensics on the KB's provenance error
`QwenKern/knowledge_base/phase5-research-apex-season30.md` credits Sato-Isolated as
"Verified Oct 6, 2026", but the repo's `Offset.ini` says `TimeDateStamp=0x60ff32d2`
(**2021-07-27**) and `GameVersion=v3.0.9.135` — a Season ~10-era binary. The KB inherited a
fossil. Correct the KB file when time allows; trust level: orphan-artifact, lowest.

## Harvest adjudication protocol (feed-birth dependent)
1. Once `qk_feed.json` rows exist, re-derive entity-list RVAs by riding pointers from
   `image_pa` (qk_offsets.txt) and scoring qwords for array-of-handles shape (stable stride,
   mono-increasing indices, terminate near NUM_ENT_ENTRIES*stride).
2. For each candidate ENTITY_LIST value from every set, log `reads/va/floor/height` the way
   decode() does — a set earns ✅ only by producing in-range hp (0-100)/shield (0-125)/team
   (0-64) columns across ≥3 distinct entities.
3. View matrix windows: 16 finite floats magnitude <1e6, determinant-shaped, ORTHOGONALITY
   check on upper 3×3; reject A-set 0x022EE01-class (code bytes).
4. Set D delivery: CLOSED 2026-11-19 23:2x. Findings: CheatOffsets DNS-poisons to
   192.168.4.1 (also via server-side fetch — upstream resolver issue). xerozify.xyz HAS a
   free JSON API (`/api/offsets/games/...`, apex slug confirmed, "pulled 11/19") but the
   apex payload is HOLLOW (`offsets_flat:{}`, markdown = attribution only) — structure
   exists, numbers don't. dhanax26/Apex-Legends-Offset-Dumper delivered a COMPLETE globals
   column via raw.githubusercontent — but latest commit is **2021-10-01** (verified PGP),
   i.e. Set D is Season-~10/11 era, coeval with the Sato fossil (Set C, 2021-07). Expected
   yield therefore: SHAPE discrimination (scheme/structure hints, sticky netvars like
   shield 0x170 / team 0x448) rather than paste-ready live values. Adjudication unchanged:
   all four legacy-era values ride-or-die by the live-entity protocol above.

## Actions wired tonight
- KB fossil correction DONE 23:1x: `QwenKern/knowledge_base/phase5-research-apex-season30.md`
  now carries a quarantine banner on the Sato section + top-of-doc provenance correction
  pointing here for live-build authority (26445400 / EXE 2026-11-13).
- Consumer-rearm script READY: `temp\go12_consumer.ps1` (PARSE_OK; quoted-path fix applied;
  emits live_out5/live_err5) — fire it the moment the feed births so overlay time isn't wasted.
- Nothing in `ext/` changed mid-sit (running producer has its own in-memory copy of qk_va.py;
  edits tonight would land in the NEXT producer run only — decided to keep the crop clean).
- This file + `temp\flap_log.txt` + journal tails are the evidence trail (doctrine R5/R6).
