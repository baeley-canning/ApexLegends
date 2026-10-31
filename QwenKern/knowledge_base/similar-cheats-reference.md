# Similar Cheats - Reference Guide

**For:** Next developer/assistant  
**Last Updated:** October 14, 2026  
**Project Location:** `C:\Users\New User\OneDrive\Desktop\QwenKern\`

---

## Cheats Analyzed by User

### 1. Kernaim
**Pattern Matched:** Tabbed menu with Aimbot, Visuals, Misc, Colors tabs

**Key Features:**
- Tabbed interface matching Ignite/Chudvision patterns
- Internal D3D overlay rendering
- Shared memory IPC for configuration sync
- Legend-specific configurations (Wraith tight, Gibraltar loose)
- Humanizer pipeline for behavioral evasion

**UI Pattern:**
```
┌─────────────────────────────────────┐
│ Apex Legends Cheat Menu             │
├─────────────────────────────────────┤
│ [Aimbot] [Visuals] [Misc] [Colors]│
├─────────────────────────────────────┤
│                                     │
│  (Content varies by tab)           │
│                                     │
└─────────────────────────────────────┘
```

**Relevance to Project:**
- Primary reference pattern for Phase 3 menu system
- SharedMenuData structure matches Kernaim's configuration approach
- Legend-specific overrides implemented per Kernaim pattern

---

### 2. Ignite
**Pattern Matched:** Similar tabbed interface to Kernaim with humanizer pipeline

**Key Features:**
- Clean ImGui-style UI matching Kernaim/Ignite/Chudvision
- Humanizer pipeline for behavioral evasion
- Legend-specific configurations
- Smooth transitions and animations
- Color customization per team/enemy/downed

**Relevance to Project:**
- UI design pattern directly adopted in Phase 3
- Evasion patterns inform Javelin detection avoidance
- Human baseline statistics (N(250ms, σ=75ms) reaction time)

---

### 3. Chudvision
**Pattern Matched:** Clean ImGui-style UI with ESP rendering

**Key Features:**
- Clean ImGui-style UI matching Kernaim/Ignite patterns
- ESP with boxes, glow, skeletons for all legends
- Legend-specific configurations
- Color customization per team/enemy/downed
- Smooth transitions and animations

**Relevance to Project:**
- ESP overlay design pattern (Phase 4)
- Box styles: Outline, Filled, Corner, Rounded, Dashed
- Glow intensity and skeleton rendering configurable

---

### 4. Aurora (User's Purchased Cheat)
**Location:** `C:\Program Files\EA Games\Apex`  
**Pattern Matched:** Internal overlay with Javelin-compliant behavior

**Key Features:**
- Internal overlay rendering (not external popup windows)
- Javelin-compliant behavior
- Clean UI with minimal detection footprint
- Runs at same location as user's cheat installation

**Relevance to Project:**
- User's reference for "proper" internal overlay
- Confirmed that internal D3D overlay is detectable by Javelin but not flagged
- Shows user's expectations for overlay rendering

---

## Comparison Matrix

| Feature | Kernaim | Ignite | Chudvision | Aurora (User's) | This Project |
|---------|---------|--------|------------|-----------------|--------------|
| **UI Style** | Tabbed ImGui | Tabbed ImGui | Tabbed ImGui | Internal D3D | Tabbed ImGui |
| **Overlay Type** | Internal D3D | Internal D3D | Internal D3D | Internal D3D | Internal D3D |
| **Tab Pattern** | Aimbot, Visuals, Misc, Colors | Same | Same | Same | Same |
| **ESP Features** | Boxes, Glow, Skeletons | Boxes, Glow, Skeletons | Boxes, Glow, Skeletons | Boxes, Glow, Skeletons | Boxes, Glow, Skeletons |
| **Legend Configs** | ✅ Per-Legend overrides | ✅ Per-Legend overrides | ✅ Per-Legend overrides | ✅ Per-Legend overrides | ✅ Per-Legend overrides |
| **Humanizer** | ✅ Reaction time + micro-jitter | ✅ Full pipeline | ✅ Basic implementation | ✅ Active | ✅ Planned |
| **Detection Risk** | Low-Medium | Low-Medium | Low-Medium | Low | Low-Medium |

---

## UI Pattern Reference

### Tabbed Menu Structure
```
┌─────────────────────────────────────────────┐
│ Apex Legends Cheat Menu                     │
├─────────────────────────────────────────────┤
│ [Aimbot] [Visuals] [Misc] [Colors]        │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────────────────────────────┐  │
│  │  Aimbot Tab Content                 │  │
│  │  - Enable Aimbot (UNSAFE)           │  │
│  │  - Aim Keys (LMB, LCtrl)            │  │
│  │  - FOV Size: 22.0                    │  │
│  │  - Max Dynamic FOV: 200             │  │
│  │  - Smoothing X/Y                     │  │
│  │  - Legend-Specific Overrides        │  │
│  └─────────────────────────────────────┘  │
│                                             │
│  Status: Active | Version: 1.0.0          │
└─────────────────────────────────────────────┘
```

### ESP Overlay Pattern
```
Game Screen → [D3D Hook] → [ESP Renderer]
                             ↓
                  ┌──────────────────┐
                  │ Boxes (Outline/   │
                  │ Filled/Corner)    │
                  │ Glow Intensity    │
                  │ Skeletons         │
                  │ Health Bars       │
                  │ Distance Labels   │
                  │ Snaplines         │
                  └──────────────────┘
```

---

## Key Takeaways for New Developer

1. **Pattern Recognition:** All reference cheats (Kernaim, Ignite, Chudvision) use similar tabbed ImGui structure - this is the expected pattern.

2. **Internal Overlay is Standard:** User's Aurora cheat and reference cheats all use internal D3D overlay - external popup windows are secondary.

3. **Legend Configurations Matter:** Each cheat supports per-Legend overrides - Wraith tight, Gibraltar loose pattern is standard.

4. **Humanizer Pipeline:** Behavioral biometrics (reaction time, micro-jitter) are key for Javelin evasion - implement per Phase 2 research.

5. **ESP Rendering Consistent:** Boxes, glow, skeletons are the standard ESP features across all reference cheats.

---

## File Locations Reference

### Reference Cheat Locations
- **Kernaim/Ignite Pattern:** `phase3_menu_system/imgui_integration/`
- **Chudvision ESP:** `phase4_esp_overlay/`
- **Aurora (User's):** `C:\Program Files\EA Games\Apex`

### Code Patterns to Match
- **Tabbed Menu:** `menu_core.cpp` - RenderMainMenu() with tab bar
- **ESP Rendering:** `esp_renderer.cpp` - RenderESP() with boxes/glow/skeletons
- **Legend Configs:** `menu_config.hpp` - LegendConfigs[12] array

---

**Status:** Reference patterns documented for Phase 3-4 implementation.
