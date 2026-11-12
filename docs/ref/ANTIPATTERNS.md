# ANTIPATTERNS

A1  Hardcoded offset in shipping code. Cache or reload, never inline.
A2  Uniform-delta correction. Shield is +0x01C, skydive +0x4D0 in the pack; in
    dm32 four DT_Player state fields are exactly -0x8 while six whole clusters are
    exactly 0x0. Applying one correction everywhere is wrong in both directions.
A3  m_localOrigin (0x18) used for players instead of an absolute origin. Players
    carry m_localOrigin at 0x20 (DT_LocalPlayerExclusive), not 0x18. Either way
    it is cell-relative and puts entities at map origin.
A4  Adding a netvar offset to a module offset. Two namespaces, never sum them.
A5  Building from one source alone. There are three: pack, dm11/dm13/dm32 dumps,
    live read.
A6  Assuming bone ESP. Netvars carry no bones; studioHdr is 0xFD0 and separate.
A7  Declaring success from a screenshot with no tracking test.
A8  Reading geometry before filtering on m_lifeState / m_iHealth.
A9  Confidence from 2 samples. 8 samples and 3 cluster members minimum.
A10 Highlight contexts held without free-on-death - the pool silently hits its cap.
A11 Probing past P+0x400 in T3B; beyond that is a different subsystem.
A12 Deref a candidate before the heap-range check.

## Local additions - each one measured in this tree

A13 Reading a stale output file as fresh. Numbered probe, numbered output, and a
    file with no RESULT:/VERDICT: line is not evidence.
A14 Scoring PASS when the game-dependent half did not run. Print SKIPPED, score
    PARTIAL. AGENTS.md R9.
A15 Arming a long probe in a shell you will close, or rebooting with a probe
    armed. _mk16b finished its dumps and then died with its parent shell.
A16 Generalising a cluster delta. Four fields moved -0x8 and six whole clusters
    moved 0x0. 'Four agree, apply everywhere' corrupts the six.
A17 Using a sub-struct offset as an entity offset. m_vecMins 0x10 / m_vecMaxs 0x18
    are relative to m_Collision 0x3C8 on DT_BaseEntity (absolute 0x3D8/0x3E0); on
    DT_CollisionProperty they are 0x10/0x18 standalone. Two wrong sums here draw
    nothing, silently.
A18 Treating a dm32 row with off=0x00000 as an address. m_vecAbsOrigin on
    DT_Player (L2854) is off=0 sz=8 t=0x0002 fl=0x0030 and m_classModsActive /
    m_passives are the same shape: reconstruction gaps. Mark UNRESOLVED.
A19 Believing PLAN_MASTER's BLOCKER 2 ('no memory dump exists, nothing static can
    start'). dm32 already reconstructed the datamap statically. 179 classes, 3226
    fields, 2326 named - no game required.
