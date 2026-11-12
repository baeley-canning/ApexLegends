# TICKETS_LOOT - branch L

Depends on: T4 green. Locally measured rows only, class attached. Same contract.

L0  LOOT ENTITIES. m_tier 0x1630 (DT_LootRoller L1302). Note the pack number for
    this field is 0x16F0 - a -0x00C0 delta, so a global -0x8 correction misses it.
    ACCEPT: tier values seen are only the legitimate set (1..4 plus 0), across 8+
    samples. BLOCK: tier reads random large ints (wrong class).

L1  ARMOUR / AMMO TYPE. m_armorType 0x48D8 on DT_Player (the LOCAL player's own
    armour) vs 0x16D4 on DT_ScriptProp (L3509) vs the pack 0x16E4. m_ammoType
    0x1655 on DT_ArsenalProp (L3651). Three classes, three answers - pick per class.

L2  DEATH BOX. DT_DeathBoxProp: m_customOwnerName 0x1650 sz 0 (L3552), m_lifeState
    0x698 (L3549), m_iTeamNum 0x340 (L3550), m_iSignifierName 0x478 (L3533).
    ACCEPT: owner name is a readable ASCII string on 3 different boxes. BLOCK:
    name reads as garbage - it is an embedded string, not a pointer.

L3  DEATH FIELD. m_deathFieldIndex 0x4BA0 on DT_LocalPlayerExclusive (L2688) -
    pack names m_deathFieldIsActive / m_deathFieldRadius are ABSENT from dm32.
    Do not invent them.

L4  LOOT GLOW. m_impactEffectColorID 0x1650 sz 1 on DT_LootGrabber (L3559) -
    same offset as m_customOwnerName on DT_DeathBoxProp but a DIFFERENT size and
    class. Overlap without class again.

L5  HIGHLIGHT. m_highlightFocused 0x2A8 sz 1 and m_highlightFadeParity 0x2B4 sz 4
    on DT_HighlightSettings (L2279/L2281). The named row for FadeParity is sz 4 -
    if the glow flickers, this is the field to look at. Pack's
    m_highlightGenericContexts 0x2A0 has no named row; unnamed slots exist at
    0x2A0..0x2EC, so the block IS present.
