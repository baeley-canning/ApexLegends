# BACKLOG - deliberately out of scope, recorded so nobody re-derives it

Bones       studioHdr 0xFD0, m_SequenceTransitioner 0xB20. Needs the studio/model
            path, not netvars.
Aimbot      m_viewangle 0x25C8, m_vecPunchWeapon_Angle 0x24D8,
            m_vecPunchWeapon_AngleVel 0x24E4. Needs a verified origin first.
Projectiles DT_Projectile 0x1906 carries m_localOrigin 0x18, m_nModelIndex 0x64,
            m_CollisionGroup 0x438. m_launchOrigin 0x1624, m_vecVelocity 0x384,
            m_projectileSpeed 0x2D68.
Spectators  observerList 0x6B53478, observer_index 0x94.
ConVars     see REF_TABLE; 3773 entries were captured in an earlier dump.
Physics     sv_friction, sv_airaccelerate, m_flMaxspeed 0x334 (local, DT_Player).
Names       string table / 46957 strings in the image - needed for m_iSignifierName
            and weapon names, and it is the only way to turn m_nModelIndex into text.
Zone        m_WorldMins 0x940 / m_WorldMaxs 0x94C exist (DT_World). Zone needs the
            world-space -> minimap transform, which is a separate RE task.
