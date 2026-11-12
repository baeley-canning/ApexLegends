# TICKETS_INFRA - T0..T3E

Every ticket: BLOCK is a stop-and-report condition. Every ticket carries its own
reverse. Every ticket must print PRE and POST state.

T0  BEACON. Prove that a physical read at image_pa + rva for a known string/const
    returns the expected bytes. PRE: none. DO: derive image_pa from the process's
    MZ + sections, read one known constant, compare. ACCEPT: exact match on a 16-byte
    window and a stable value across 3 reads. BLOCK: two candidate image_pa with both
    plausible. REVERSE: nothing (read-only).

T1  MODULE BASE + VIEW MATRIX. DO: read the 16 floats at image_pa + VP_RVA
    (measured locally 0x0DB5BC40; pack says 0x11A390 - do NOT average them). ACCEPT:
    row 3 is 0/0/0/1 and the basis is orthonormal. BLOCK: values are sane but the
    '1' wanders. REVERSE: read-only.

T2  LOCAL PLAYER. DO: resolve the local-player pointer, then read m_iHealth at
    +0x330 with the dm32 class in hand (DT_Player). ACCEPT: hp in 1..200 range and
    changes when damaged. BLOCK: pointer walks but hp reads 0 on every candidate.

T3A THE CHEAP RUNG. Take the CHLClient/engine path to the entity array first.
    This is the DEFAULT. The blind sweep below is the FALLBACK, not the plan.
T3B BLIND SWEEP. Scan a window for array-shaped candidates, depth first, deref only
    after the heap-range check. Never probe past P + 0x400 in one hop (A11).
T3C SETTLE pointer-to-array vs array itself. Do not assume either.
T3D THE LOAD-BEARING RUNG. Find an index whose deref yields an entity whose
    m_iHealth and m_iTeamNum are both plausible, and which is NOT index 0 or 1, and
    which contains the LOCAL player. This is the only rung that separates the true
    array from an observer list or a replay copy.
T3E CAP. Edict count: retire the hard 20000 cap. Floor 0x4000, and prefer MaxEdicts
    read from the header over any constant.

GATE T4: one box on screen around a live player, stable for 30 s, surviving one
respawn. If T4 fails, stop - do not start S1 content work.
