# PLAN_MASTER - the corpus plan, re-based on this tree

FORK NOTE, read first. The corpus was written for an INTERNAL fork: DLL injected into
the game, D3D12 Present hook, cl.exe, 'attach' as T0. Our tree is EXTERNAL: python
probes in temp\, gdrv3 physical reads, static reads at image_pa + rva, no DLL. The
OFFSETS are shared between forks. The TRANSPORT is not. Names and structure come from
the corpus; transport comes from PLAN.md.

## Blockers, re-stated honestly

BLOCKER 1  Q1 probe never ran against a live pid. TRUE.
BLOCKER 2  'No memory dump exists, nothing static can start.' FALSE HERE.
           temp\dm32.txt is a static datamap reconstruction of the shipping image:
           179 classes, 3226 fields, 2326 named, per-class blocks with off/sz/t/fl and
           line numbers. Static work starts now with no game and no launch.
BLOCKER 3  T0 beacon unproven. TRUE, but now testable against dm32 instead of against
           a guess.

## Stage ladder (each stage must change a pixel or it is not a stage)

S0  infra   T0 beacon -> T1 module base + view matrix -> T2 local player ->
            T3A..T3E entity array ladder. GATE: T4 - one box on screen over a live pid.
S1  box     world -> screen projection, 2D box from mins/maxs, alive filter.
S2  bars    health + shield bars off the verified health/shield cluster.
S3  state   name, distance, bleedout/sprint/duck/skydive flags (the -0x8 cluster).
S4  weapons weapon name, ammo, owner.
S5  loot    tier, armour type, custom owner name.
S6  glow    highlight block, bounded fallback (see below).
S7  zone    world bounds + minimap transform.

Order is fixed: T4 gates everything after S0. Branches G (glow), W (weapons) and L
(loot) are INDEPENDENT once T4 is green - a G1 failure must never stall W or L.

BLOCK clause, verbatim, on every ticket: a ticket that has not produced a RESULT:
line naming the variable it changed, plus a VERDICT: line, is NOT DONE.

## Bounded fallbacks

Glow: if G1 (direct per-entity highlight) fails, use the manager path (D2). If that
also fails, move glow to BACKLOG.md and stop spending evenings on it.
Ammo: if the weapon resolution needs the LocalWeaponData sub-object, take it - the
local rows prove quantity and clip live on DT_WeaponX_LocalWeaponData, not DT_WeaponX.

## Rules carried from the pack

Confidence >= 0.75, >= 8 samples, >= 3 cluster members before promotion. Lone fields
are never promoted. One variable per probe. New probe number, never overwrite output.
Read the output FILE, not the chat. Reversibility in the same script. See
docs/ref/ANTIPATTERNS.md before writing anything.
