# DELTA_MATRIX - measured, not remembered

Measured 2026-11-09 from temp\dm32.txt (static datamap reconstruction of
C:\Program Files\EA Games\Apex\r5apex_dx12.exe; 179 classes, 3226 fields,
2326 named). Pack values are corpus values, UNVERIFIED. delta = pack - local, so a
NEGATIVE delta means the corpus number is HIGHER than this build.

Local dm32 is the authority. This file is evidence; it is not a correction
recipe.

## Cluster deltas

  0x0000  health        m_iHealth 0x330, m_iMaxHealth 0x470, m_lifeState 0x698 (DT_Player)
  0x0000  team          m_iTeamNum 0x340 (DT_BaseEntity L2297 and 11 other classes)
  0x0000  shield        m_shieldHealth 0x18C / m_shieldHealthMax 0x190 (DT_BaseCombatCharacter L3111/3112)
  0x0000  identity      m_nModelIndex 0x64, m_iSignifierName 0x478, m_Collision 0x3C8,
                        m_CollisionGroup 0x438, m_visibilityFlags 0x338, m_realmsBitMask 0x900
  0x0000  world bounds  m_WorldMins 0x940, m_WorldMaxs 0x94C (DT_World L3832/3833)
  0x0000  weapons core  m_weaponOwner 0x15D0, m_weaponNameIndex 0x1880, m_iWorldModelIndex 0x15E8,
                        m_ammoInClip 0x1600, m_ammoInStockpile 0x1604, m_inventory 0x1958
  0x0000  highlight     m_highlightFocused 0x2A8, m_highlightFadeParity 0x2B4 (DT_HighlightSettings)
 -0x0008  state         m_bleedoutState 0x27A0, m_fIsSprinting 0x2A54, m_duckState 0x2AA0,
                        m_ammoPoolCapacity 0x25D4   (all DT_Player)
 -0x0060  skydive       m_skydiveIsDiving 0x4958 (DT_Player L2880)
 -0x0010  loot owner    m_armorType 0x16D4 (prop class), m_customOwnerName 0x1650
 -0x0080  loot colour   m_impactEffectColorID 0x1650 (DT_LootGrabber L3559, pack 0x16D0)
 -0x00c0  loot tier     m_tier 0x1630 (DT_LootRoller L1302, pack 0x16F0)

SIX clusters sit at 0x0000. A uniform correction - the -0x108, or even a flat
-0x8 - corrupts every one of them. That is antipattern A2, demonstrated here.

## CLASS-DEPENDENT - an offset without a class label is not a result

  m_localOrigin       0x18 (DT_BaseEntity L2288) and 0x20 (DT_LocalPlayerExclusive L2491)
  m_armorType         0x48D8 (DT_Player, the one ESP wants) and 0x16D4 (DT_ScriptProp L3509)
  m_grappleActive     0x2DC0 (DT_Player L2749) and 0x1F10 (DT_WeaponInventoryActiveWeaponOnly L1057)
  m_nModelIndex       0x64 (DT_BaseEntity) but 0x5C / 0x4C on the TE_* event classes
  m_vecMins/m_vecMaxs relative to m_Collision 0x3C8 on DT_BaseEntity - absolute
                      0x3D8 / 0x3E0 - but 0x10 / 0x18 standalone on DT_CollisionProperty

Adding 0x10 for m_vecMins straight onto a player base is A17 and draws nothing.

## ABSENT from dm32 (named rows only; may exist as an unnamed slot)

  m_rgflCoordinateFrame   pack 0x7C8   no rgfl row anywhere in 4580 lines
  m_highlightGenericContexts   pack 0x2A0   DT_HighlightSettings block has unnamed rows
                          at 0x2A0-0x2EC (sz 4..0x20) - present but not named
  m_deathFieldIsActive / m_deathFieldRadius   only m_deathFieldIndex 0x4BA0 survives

## UNRESOLVED - do not silently adopt the pack value

  m_vecAbsOrigin  DT_Player L2854 renders as off=0x00000 sz=0x008 t=0x0002
                  fl=0x0030. off=0 is a reconstruction gap, not an address.
                  The corpus 0x170 is UNVERIFIED until a live read proves it.
  m_classModsActive 0x00000, m_passives 0x00000 (DT_Player) same shape.

## Pack values with no local counterpart at all

  module-relative (dm32 cannot answer; N/A never MATCH): ViewMatrix 0x11A390,
  EntityList 0x6B51458, LocalPlayer 0x24D1B80, observerList 0x6B53478.
  Measured VP in this tree is image_pa + 0x0DB5BC40 - a LOCAL number, not the
  pack number, and the pair must not be averaged.

## Pre-state you must not recompute

  dm32 summary (temp\dm32.txt L4577-4578): named fields 2326, total nfields 3226.
  Measured on the file itself: 3226 field rows, all parse, 0 malformed; 2317 carry a
  quoted name; 909 are '(null)' unnamed rows; 1 duplicate (class,name) pair; 157 named
  rows sit at off=0x0 (e.g. m_iHealth in DT_WaterLODControl). The summary's 2326 is
  therefore NINE HIGHER than the 2317 names physically present - a source-internal
  inconsistency to carry as-is, never to smooth over.
  temp\_fields_dm32.txt (2061 lines) is LOSSY: it dropped 1165 rows and has no sz=
  column. It is an index of convenience only. The lossless index is
  temp\_p146_full.txt (built by temp\_p146_full.py: 179 blocks / 3226 rows, class and
  source line on every row). There are no multi-line names. DT_Player is headed twice
  (L2735 array=0x14e6b2788 n=173, L2911 array=0x14e6b0c50 n=65) - two DIFFERENT maps,
  so the index suffixes the second block '#2' and a DT_Player offset is meaningless
  until its block is named.
