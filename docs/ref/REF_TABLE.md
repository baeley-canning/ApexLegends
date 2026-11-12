# REF_TABLE - name authority for the corpus pack

EVERY VALUE HERE IS UNVERIFIED. Values came from a 26174491-era dump and netvar
dump, not from this build. This file answers 'what is the field CALLED'; for 'what
is it at on THIS build' see docs/ref/DELTA_MATRIX.md, and the authority is
temp\dm32.txt (static datamap reconstruction of r5apex_dx12.exe).

Two namespaces. Never sum a netvar offset and a module offset (A4).

## Module-relative (image base + rva; dm32 cannot answer these)

  ViewMatrix          0x11A390     our measured VP: image_pa + 0x0DB5BC40
  EntityList          0x6B51458
  LocalPlayer         0x24D1B80
  observerList        0x6B53478
  Names / string table   (see BACKLOG - 46957 strings present in the image)
  sv_gravity          0x3EE50F0
  sv_maxspeed         0x3EE0810
  sv_friction         0x3EAB420
  sv_airaccelerate    0x3EDD1A0

## Entity-relative - health / identity

  m_iHealth           0x330     m_iMaxHealth 0x470     m_lifeState 0x698
  m_iTeamNum          0x340     m_shieldHealth 0x18C    m_shieldHealthMax 0x190
  m_iSignifierName    0x478     m_nModelIndex 0x64      m_Collision 0x3C8
  m_vecMins           0x10 (relative to m_Collision)   m_vecMaxs 0x18 (same)
  m_WorldMins         0x940     m_WorldMaxs 0x94C
  m_rgflCoordinateFrame 0x7C8   (ABSENT from dm32 - see DELTA_MATRIX)

## Entity-relative - origin / state

  m_vecAbsOrigin      0x170   (UNRESOLVED: dm32 gives DT_Player off=0x00000 sz=8)
  m_localOrigin       0x18    (cell-relative; players actually carry 0x20)
  m_bleedoutState     0x27A8
  m_fIsSprinting      0x2A5C
  m_duckState         0x2AA8
  m_bZooming          0x1CB1
  m_skydiveIsDiving   0x49B8
  m_grappleActive     0x2DC8

## Entity-relative - weapons

  m_weaponOwner 0x15D0   m_weaponNameIndex 0x1880   m_iWorldModelIndex 0x15E8
  m_ammoInClip 0x1600    m_ammoInStockpile 0x1604    m_ammoPoolCapacity 0x25DC
  m_inventory 0x1958

## Entity-relative - loot

  m_ammoType 0x1655   m_armorType 0x16E4   m_tier 0x16F0
  m_customOwnerName 0x1660   m_impactEffectColorID 0x16D0

## Entity-relative - highlight

  m_highlightFocused 0x2A8   m_highlightFadeParity 0x2B4
  m_highlightGenericContexts 0x2A0
  m_highlightTeamBits / m_highlightIndex / m_highlightFadeDuration  (names used by
  the manager path; not named in dm32 either - treat as pack-only until proven)

## Entity-relative - death / misc

  m_deathFieldIsActive 0x988   m_deathFieldRadius (pack)   m_deathFieldIndex (0x4BA0 local)
  m_flMaxspeed 0x334   m_fFlags 0x0C8   m_hGroundEntity 0x32C

## Local-only rows dm32 adds that the pack lacks (free, use them)

  m_visibilityFlags 0x338      m_realmsBitMask 0x900      m_CollisionGroup 0x438
  m_helmetType 0x48D4          m_extraShieldHealth 0x3030   m_extraShieldTier 0x3034
  m_tempShieldHealth 0x302C    m_skydiveState 0x493C        m_skydiveSpeed 0x495C
  m_glideMeter 0x3058          m_reviveTarget 0x4AB8       m_melee 0x3318

All local-only rows carry their class in DELTA_MATRIX.md / NETVAR_LOCAL.md. Do not
use one without the class.
