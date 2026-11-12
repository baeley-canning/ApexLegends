# TASK_STATE - W1/W2 corpus authoring + first live transport (2026-11-09)

Append-only-ish scratch state for this sitting. `PLAN.md` still owns "what next";
this file only records what was measured, by which file, with which verdict.

## Files created this sitting

  temp\_p146_full.py        lossless indexer for temp\dm32.txt
  temp\_p146_full.txt       179 block headers / 3226 rows / 2317 named / 909 unnamed
  temp\_p147_netvar.py      renders the two docs below from the index (regenerable)
  docs\ref\NETVAR_LOCAL.md every field, class-labelled, ref-name digest on top
  docs\ref\FIELD_MAP_LOCAL.md REF_TABLE name vs dm32, per class, delta + status
  temp\_mk17.py             wait-driver: --preflight / --wait-pid=N / --pid=N
  temp\_mk17_out.txt        its state feed (R3)

## Preflight (passing, 09:13:03) - record kept here because _mk17 truncates its own file

  RESULT: ram_top_ok=1 ranges=5 reads=3 fails=2
  VERDICT: PASS - transport alive
  ram_top=0x800000000 (32 GiB), note="clean", ranges=5
  read pa=0x000001001000 -> 98 00 60 6c 47 b3 00 00
  read pa=0x00000ffffff0 -> ERR 1450 (the measured transient; Reader retries 6x)
  read pa=0x00007ffffff000 -> ERR 1450
  Device \\.\GIOV3 opened elevated; gdrv3 untouched (R1: no load/DSE/service work).

## Live run (in flight)

  pid 14008 found after 215 s at 09:17:31. `get_map` entered 09:17:31: cache miss ->
  driver path refused -> discovery. The name sweep closed on its own at 09:19:53
  (see the numbers below) and the run has been in the candidate/PEB/pml4 tail since,
  silent because `out()` writes to stdout while only `say()` reaches this file.
  Game process confirmed alive (rss 8906 MB) at 09:50; child CPU climbs every poll,
  so it is working, not deadlocked. Verdict pending.

  Lesson for the next script in this family: `out()` and `say()` must share one sink,
  otherwise a 30-minute discovery phase is indistinguishable from a hang. That is the
  same failure R3 exists to prevent.

## Source corrections made this sitting (both were believed wrong before)

  1. temp\_fields_dm32.txt was called "an index". It is LOSSY: 2061 lines against
     3226 rows = 1165 rows missing, and no sz= column. DELTA_MATRIX L66-69 blamed
     "multi-line names" for the gap; there are no multi-line names. Rewritten there.
  2. "179 classes" is really 178 classes in 179 blocks: DT_Player is headed twice
     (L2735 array=0x14e6b2788 n=173, L2911 array=0x14e6b0c50 n=65) - two different
     datamaps. Index now suffixes the second '#2'. A DT_Player offset without its
     block is ambiguous, including the m_armorType 0x48d8 every box depends on.
  3. dm32 summary says 2326 named, the file carries 2317. Nine-row source-internal
     inconsistency, carried as-is, not reconciled.

  Also real: 909 unnamed rows, 157 named rows parked at off=0x0, sz=0xffffffff /
  t=0xffffffff used as "unknown" wildcards (268 rows), so a wide numeric parser is
  mandatory - a 4-hex regex silently eats them.

## Transport numbers, run pid 14008 (09:17:31 launch, sweep closed 09:19:53)

  SCANEND scanned=28411 MiB chunks=454583 hits=4 fault=348421 rescued=547947 357.1s
  hits cache temp\qk_hits_14008.txt: 2D87FB490 / 3B56FD448 / 5B3AEDE0B / 6FB6A7BC0
  (physical PAs of ImageFileName). This is the first hard number for `name_hits` on
  this build: 357 s for a full 28.4 GiB pass at 64 KiB/ioctl, no throttle, and it
  terminates on its own. So the sweep is NOT the reason `get_map` looks hung - the
  twenty-plus silent minutes are the DTB-candidate -> PEB/pml4 tail, whose caps are
  120 s per candidates pass / 900 s per PEB window / 240 s per pml4 walk. A run that
  prints nothing for 30 min is inside those caps, not looping.
  Four hits is thin (earlier runs 11192/20268 cached happily, 18196 got 6). If this
  run fails, the shape to suspect first is `_candidate_dtbs` finding no EPROCESS at
  any of the four, not the transport.

## Blocked

  Nothing technical. Awaiting the in-flight map; then vp x world -> screen rect is
  the only remaining step of the approved plan.
