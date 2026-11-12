# TICKETS_WEAPONS - branch W

Depends on: T4 green. All offsets below are LOCALLY MEASURED (docs/ref/DELTA_MATRIX.md,
temp\dm32.txt) with their class attached. Every ticket prints PRE and POST, writes its
own numbered output file, and has a RESULT: line naming the variable it changed.

W0  LOCAL HELD WEAPON. From the local player entity, read m_inventory 0x1958 and
    m_weaponOwner 0x15D0 (DT_Player L2745/L2069 area - owner lives on DT_WeaponX).
    ACCEPT: the resolved pointer is a heap pointer whose m_weaponOwner round-trips
    back to the local player address. BLOCK: round-trip fails - means you resolved
    the inventory array, not a weapon. REVERSE: read-only.

W1  WEAPON NAME. m_weaponNameIndex 0x1880 (DT_WeaponX L2073) is an INDEX, not a
    pointer: it needs the string table (BACKLOG 'Names', 46957 strings in image).
    ACCEPT: two different weapons give two different, stable strings. BLOCK: index
    reads plausible but every weapon gives the same string (wrong table).

W2  AMMO. Clip and stockpile live on the LocalWeaponData sub-object, NOT on
    DT_WeaponX: m_ammoInClip 0x1600 and m_ammoInStockpile 0x1604 are DT_WeaponX_
    LocalWeaponData rows (L2047/L2048). Pool capacity is m_ammoPoolCapacity 0x25D4
    on DT_Player L2746. ACCEPT: firing decrements clip by exactly 1, reload moves
    stockpile -> clip. BLOCK: clip never changes (wrong sub-object).

W3  WORLD MODEL. m_iWorldModelIndex 0x15E8 (DT_WeaponX L2064) selects the world
    model - needed only if the weapon is drawn as a separate entity. Skip until S1
    is on screen.

W4  CLASS LABELLING. Every weapon read must be made through a candidate set that
    excludes DT_PropSurvival and DT_ArsenalProp, which carry overlapping names at
    DIFFERENT offsets (m_ammoInClip 0x15D0 on DT_PropSurvival L3477 vs 0x1600 on
    DT_WeaponX_LocalWeaponData). Overlap without class = A2.

W5  GRAPPLE (bonus, cheap). m_grapple 0x2D38 / m_grappleActive 0x2DC0 on
    DT_Player L2749  - class-dependent: 0x1F10 on DT_WeaponInventoryActiveWeaponOnly.
