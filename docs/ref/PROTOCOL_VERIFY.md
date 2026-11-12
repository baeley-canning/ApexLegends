# PROTOCOL_VERIFY - how an offset becomes a fact

Cluster method. Membership survives insertions; absolute position does not, which is
why a cluster is verified as a SET and then placed as a set.

P1  Scan a 3-field cluster against every source available. One source will land
    plausible and the others will not.
P2  Resolve the winner on 8 or more entities. Deltas within +/-0x10 of each other
    across the cluster means located; scattered means not.
P3  If scattered, walk forward from an anchor that matches names IN ORDER. Ordering
    is the signal, not any single offset.
P4  Cross-cluster sanity: shield sign must oppose health, the view triple must be
    three contiguous floats inside -16..16.
P5  Promote clusters only, never lone fields. confidence = agreeing/samples.
    Below 0.75, or under 8 samples, or under 3 cluster members, stays UNVERIFIED.
a9 is the rule this encodes.

Module entry points resolve separately, in order ViewMatrix -> LocalPlayer ->
EntityList. A wrong EntityList still walks; the tell is that the health cluster
fails on every single entry rather than on a few.

## Local additions to this tree

P6  THERE IS A THIRD SOURCE. temp\dm32.txt is a static datamap reconstruction of
    the shipping image: 179 classes, 3226 fields, 2326 named, one '### DT_<Class>'
    block per class with per-field 'off=' 'sz=' 't=' 'fl=' and an evidence line
    number. A field confirmed there is confirmed against the BINARY, not against
    somebody else's post. Run P1 against dm32 as well.
P7  A name can legitimately exist at several offsets because several classes carry
    it: m_localOrigin 0x18/0x20, m_armorType 0x48D8/0x16D4, m_grappleActive
    0x2DC0/0x1F10, m_nModelIndex 0x64/0x5C/0x4C. AN OFFSET WITHOUT A CLASS LABEL IS
    NOT A RESULT. This is why every extracted row must carry its DT_ class.
P8  The array rung is the weak rung. A pointer array of the wrong shape, an
    observer list and a replay copy all pass a shape test. Only 'the local player
    appears in-array at a stable index above 1' separates them (T3D).
P9  Origin discipline. A world-space box needs an absolute-origin field, not a
    cell-relative one. Both failure modes look identical on screen (everything
    piled at map origin) - disambiguate by projecting ONE known point and checking
    the pixel, never by looking at the pile.
P10 Absence is a result too. 'm_rgflCoordinateFrame and m_highlightGenericContexts
    are not named in dm32' is a finding that saves a session. Write ABSENT rows
    down; do not silently drop them.
