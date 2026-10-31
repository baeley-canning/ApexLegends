# Apex Legends ESP Overlay - Research and Improvement Knowledge Base

**Last Updated:** 2026-10-22 | **Build Target:** Season 30 / Build 25682878+ | **Status:** Phase 4 Complete -> Phase 5 Planning

---

## Table of Contents
1. Current State Analysis
2. Identified Improvements (Bone ESP, Camera Tracking, Performance)
3. Offset Reference and Pattern Scanning
4. D3D12 Overlay Best Practices
5. Performance Optimization Techniques
6. Future Enhancement Roadmap
7. Known Issues and Workarounds
8. Research Sources and References
9. Quick Reference: Common Tasks
10. Bone Array Structure for Skeleton ESP (NEW)
11. View Matrix and Camera Tracking (NEW)
12. Comparative Analysis of External ESP Implementations (NEW)

---

## 1. Current State Analysis

### What We Have Accomplished (Phase 4)
- **Independent Overlay Window**: Topmost layered window (WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT) above D3D12 swap chain
- **Camera-Aware W2S**: CalculateScreenPositionWithCamera() using yaw/pitch angles and forward/right/up vectors
- **Dynamic Position Tracking**: UpdateOverlayPosition() follows game window changes
- **Entity Extraction**: Pattern scanning for entity list and local player pointers in r5apex.exe
- **Basic ESP Features**: Box rendering, health/shield bars, team colors, distance indicators

### Current Offsets (entity_extractor.cpp)
| Field | Offset | Type | Notes |
|-------|--------|------|-------|
| Entity List Pointer | Pattern-scanned | uint64_t | mov rax, [rip+XX] pattern |
| Local Player | Pattern-scanned | uint64_t | mov rax, [rip+XX] pattern |
| Entity Count | +0x18 | uint32_t | From entity list base |
| Entity Array | +0x28 | uint64[] | 8-byte stride per entity |
| Base Entity | +0x0 (dereference) | uint64_t | First deref of entity ptr |
| Player Name | +0x58 | string | UTF-8, max ~64 chars |
| Account ID | +0x1D0 | uint32_t | Steam/EA account ID |
| Position | +0x2A0 | XMFLOAT3 | World space XYZ |
| View Angles | +0x2BC | XMFLOAT3 | Yaw/Pitch/Roll radians |
| Health | +0x868 | uint32_t | Current health |
| Max Health | +0x86C | uint32_t | Maximum health |
| Shield | +0x970 | uint32_t | Current shield |
| Max Shield | +0x974 | uint32_t | Maximum shield |
| Shield Cells | +0x978 | uint32_t | Shield cell count |
| Movement Speed | +0x34C | float | Units per second |
| Stance | +0x358 | uint32_t | 0=stand, 1=crouch, 2=prone |

---

## 2. Identified Improvements (Prioritized)

### PRIORITY 1: Skeleton/Bone ESP Rendering [HIGH]
**Why:** Box ESP is basic; skeleton ESP provides precise player positioning and looks professional.

**Implementation Plan:**
- Read bone array from entity (offset ~0x1A90+, varies by build)
- Render bone connections as D3D11 lines (D3D11_PRIMITIVE_TOPOLOGY_LINELIST)
- Apply per-bone visibility check (compare lastVisibleTime with current time)
- Color-code bones: green = visible, red = hidden

**Bone Chain Structure:**
0=Head, 1=Neck, 2=Chest, 3=Pelvis, 4=L_UpperArm, 5=L_LowerArm, 6=L_Hand
7=R_UpperArm, 8=R_LowerArm, 9=R_Hand, 10=L_Thigh, 11=L_Calf, 12=L_Foot
13=R_Thigh, 14=R_Calf, 15=R_Foot

**Connection Pairs:**
{0,1},{1,2},{2,3} - Spine | {1,4},{4,5},{5,6} - Left Arm | {1,7},{7,8},{8,9} - Right Arm
{3,10},{10,11},{11,12} - Left Leg | {3,13},{13,14},{14,15} - Right Leg

**Files to Modify:** entity_extractor.hpp (add bone struct), entity_extractor.cpp (bone reading), esp_renderer.hpp/cpp (line rendering)

### PRIORITY 2: Camera Position Tracking [MEDIUM-HIGH]
**Why:** Current W2S uses entity view angles; camera position from local player is more accurate.

**Implementation Plan:**
- Read camera position from local player view matrix or camera component
- Use m_currentFrameLocalPlayer structure for camera data
- Update camera position every frame (changes with head movement)
- Implement improved W2S using full 4x4 view matrix instead of manual yaw/pitch

**Improved W2S Formula:**
cpp
Vector4 clip;
clip.x = world.x * viewMatrix[0][0] + world.y * viewMatrix[0][1] + world.z * viewMatrix[0][2] + viewMatrix[0][3];
clip.y = world.x * viewMatrix[1][0] + world.y * viewMatrix[1][1] + world.z * viewMatrix[1][2] + viewMatrix[1][3];
clip.w = world.x * viewMatrix[3][0] + world.y * viewMatrix[3][1] + world.z * viewMatrix[3][2] + viewMatrix[3][3];
if (clip.w < 0.1f) return Vector2{-1, -1}; // Behind camera
Vector2 ndc = {clip.x / clip.w, clip.y / clip.w};
return {(screenWidth/2)*ndc.x + ndc.x + screenWidth/2, -(screenHeight/2)*ndc.y + ndc.y + screenHeight/2};

**Research Source:** Haeryz/Apex-external-driver W2S implementation

### PRIORITY 3: Performance Optimizations [MEDIUM]

#### A. Entity Caching
cpp
struct CachedEntity { uint64_t address; uint32_t version; PlayerData data; };
std::unordered_map<uint64_t, CachedEntity> entity_cache_;
// Only read entities that changed (check version/timestamp)


#### B. Batch Memory Reads
cpp
struct PlayerDataBlock { uint64_t base_entity; uint64_t name_ptr; uint32_t account_id; float position[3]; ... };
ReadProcessMemory(process_handle_, entity_ptr, &data_block, sizeof(data_block), nullptr);
// Single read instead of 15+ individual reads (60-70% reduction)


#### C. FPS Limiter with Adaptive Rate
cpp
int target_fps = is_in_match ? 30 : 60; // Lower in match to reduce CPU usage
QueryPerformanceCounter for precise timing, Sleep between frames


#### D. Selective Rendering
- Skip entities beyond max render distance (500m box ESP, 200m skeleton)
- Cull off-screen entities before W2S conversion
- Use bounding box check before expensive calculations

### PRIORITY 4: Advanced ESP Features [MEDIUM-LOW]
A. Loot/Item ESP - Parse model path for item type, rarity color-coding (Common=gray, Rare=blue, Epic=purple, Legendary=orange, Heirloom=gold)
B. Radar/Minimap Overlay - Circular mini-radar with player yaw rotation or North-up mode
C. Death Box ESP - Track death box entities, show contents for loot visibility
D. Dummy/Firing Range ESP - Dedicated color for training dummies, full skeleton support

---

## 3. Offset Reference and Pattern Scanning

### Current Pattern Scanners (entity_extractor.cpp)
**Entity List:** \x48\x8B\x05\x00\x00\x00\x00\x48\x8B\x48\x00 mask: xxx????xxxx -> mov rax, [rip+XX] + mov rcx, [rax+XX]
**Local Player:** \x48\x8B\x05\x00\x00\x00\x00\x48\x85\xC0 mask: xxx????xxxx -> mov rax, [rip+XX] + test rax, rax

### Pattern Scanning Best Practices
1. Multiple fallback patterns (2-3 per pointer) in case Respawn updates one
2. Range-limited scans to known module sections (.text, .rdata)
3. Cache results - only re-scan when game version changes or pointers become stale
4. Validate scanned offsets by checking if read values are reasonable

### Offset Update Strategy
1. Dump r5apex.exe from memory (on-disk binary is encrypted)
2. Run offset dumper (CasualX/apexdream or custom dumper)
3. Compare new offsets with current ones
4. Update pattern scanner if RIP-relative base changed

### Recommended Dumper Tools
- [Apex Offset Dumper](https://casualhacks.net/apexdream/apexdumper.html) - Web-based WASM dumper
- ReactiioN1337/Apex-Legends-Offset-Dump - GitHub gist with raw offsets
- dtzdev/offsets (read-only archive) - Historical offset data

### Latest Known Offsets (Season 30+) - May change with updates
| Field | Offset | Notes |
|-------|--------|-------|
| Entity List Base | Pattern-scanned | Varies by build |
| Local Player | Pattern-scanned | Varies by build |
| Player Position | +0x2A0 | From entity base |
| View Angles | +0x2BC | Yaw/Pitch/Roll radians |
| Health | +0x868 | Current health value |
| Shield | +0x970 | Current shield value |
| Bone Array | ~0x1A90+ | Varies by build, needs verification |
| Camera Position | View matrix or camera entity | More accurate than position offset |
| Last Visible Time | ~0x1E8+ | For visibility checks |

---

## 4. D3D12 Overlay Best Practices

### Swap Chain Configuration (Current - Correct)
cpp
DXGI_SWAP_CHAIN_DESC sd{};
sd.BufferCount = 2;
sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
sd.OutputWindow = overlay_window_;
sd.SampleDesc.Count = 1;
sd.Windowed = TRUE;
sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD; // Correct for overlay
sd.Flags = DXGI_SWAP_FLAG_ALLOW_MODELESS; // Critical for overlays


### Key Configuration Points
**DXGI_SWAP_EFFECT_DISCARD:** Best performance for overlays (no need to preserve frame content). Game uses FLIP_DISCARD or FLIP_SEQUENTIAL, overlay can use DISCARD independently.

**DXGI_SWAP_FLAG_ALLOW_MODELESS:** Allows overlay to work with other windows active. Required for proper layered window behavior.

### Fullscreen Exclusive Mode Handling
Apex Legends runs in: FSE (game takes direct control), Borderless Windowed (easier overlay), or Windowed mode.

**Workaround for FSE:** Detect fullscreen state and adjust overlay behavior, toggle WS_EX_TOPMOST on focus change, or use SetWindowPos with HWND_TOPMOST every frame.

### Click-Through Behavior
Current: WS_EX_TRANSPARENT allows mouse events to pass through. Alternative: WM_NCHITTEST for selective click-through based on whether mouse is over ESP content.

---

## 5. Performance Optimization Techniques (Detailed)

### Memory Read Optimization
**Current:** Individual ReadProcessMemory calls per field
**Optimized:** Bulk read with struct packing - Single read instead of 15+ individual reads (60-70% reduction in RPC calls)

### Rendering Optimization
**Current:** Draw every frame without culling
**Optimized:**
1. Skip entities beyond max render distance (500m for box ESP, 200m for skeleton)
2. Cull off-screen entities before W2S conversion
3. Use bounding box check before expensive calculations
4. Batch D3D11 draw calls instead of per-entity DrawPrimitive calls

### FPS Limiter with Adaptive Rate
cpp
int target_fps = is_in_match ? 30 : 60; // Lower in match to reduce CPU usage
QueryPerformanceCounter for precise timing, Sleep between frames

**Why:** Reduces CPU overhead while maintaining smooth ESP updates. 30 FPS is sufficient for ESP rendering and saves ~50% CPU compared to 60 FPS.

---

## 6. Future Enhancement Roadmap (Phase 5+)

### Phase 5: Skeleton ESP + Camera Tracking
**Skeleton ESP:** Add bone reading and line rendering for precise player positioning
**Camera Tracking:** Use full view matrix for more accurate W2S projection

### Phase 6: Advanced Features
**Loot ESP:** Parse model path for item type, rarity color-coding (Common=gray, Rare=blue, Epic=purple, Legendary=orange, Heirloom=gold)
**Radar Overlay:** Circular mini-radar with player yaw rotation or North-up mode
**Death Box ESP:** Track death box entities, show contents for loot visibility

### Phase 7: Polish and Optimization
**Performance:** Entity caching, batch memory reads, adaptive FPS limiter
**Config System:** JSON-based settings with hot-reload support
**UI Improvements:** Custom fonts, rounded corners, glow effects, animations

---

## 7. Known Issues and Workarounds

### Issue: ESP not visible in Ray Tracing mode
**Cause:** Z-buffer conflict with game render target
**Fix:** Use independent overlay window (WS_EX_LAYERED | WS_EX_TOPMOST) instead of rendering to game HWND - **RESOLVED in Phase 4**

### Issue: ESP not visible in fullscreen exclusive mode
**Cause:** Game takes direct control of display, overlay may be hidden
**Workaround:** Use borderless windowed mode for best compatibility, or toggle WS_EX_TOPMOST on focus change

### Issue: W2S misalignment (boxes offset from players)
**Cause:** Camera position not updated, or view angles incorrect
**Debug:** Print camera yaw/pitch to console, compare with in-game values. Verify entity positions match expected locations.

### Issue: ESP flickering or disappearing
**Cause:** Overlay window not properly layered, or D3D11 device lost
**Fix:** Ensure WS_EX_LAYERED is set, handle WM_DISPLAYCHANGE message, re-create swap chain on device loss

---

## 8. Research Sources and References

### External ESP Examples (Apex Legends)
1. **Haeryz/Apex-external-driver** - Reference W2S implementation, camera tracking
   https://github.com/haeryz/Apex-external-driver

2. **CasualX/Apex-Dumper** - Offset dumper, entity structure analysis
   https://casualhacks.net/apexdream/apexdumper.html
3. **ReactiioN1337/Apex-Legends-Offset-Dump** - Raw offset data for latest builds
   https://gist.github.com/ReactiioN1337
4. **dtzdev/offsets** - Historical offset archive
   https://github.com/dtzDev/offsets

### D3D12 Overlay Resources
1. **Microsoft Docs: DXGI_SWAP_EFFECT** - Swap effect types for overlays
   https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nn-dxgi-dxgi_swap_effect
2. **LearnOpenGL: Windowed Modes** - Fullscreen vs borderless windowed behavior
   https://learnopengl.com/Getting-started/Window-input

---

## 9. Quick Reference: Common Tasks

### How to Update Offsets After Game Patch
1. Dump r5apex.exe from memory (on-disk binary is encrypted)
2. Run offset dumper (CasualX/apexdream or custom dumper)
3. Compare new offsets with current ones in entity_extractor.hpp
4. Update pattern scanner if RIP-relative base changed

### How to Add New Entity Field
1. Find offset using dumper or Cheat Engine
2. Add field to PlayerData struct in entity_extractor.hpp
3. Update ReadEntity() with new ReadProcessMemory call
4. Verify offset by comparing with known-good values

### How to Debug W2S Alignment
1. Print camera yaw/pitch to console, compare with in-game values
2. Verify entity positions match expected locations (use known coordinates)
3. Check screen dimensions match actual game resolution
4. Test with player standing still (no movement compensation needed)

### How to Verify ESP Visibility
1. Launch Apex Legends with Ray Tracing enabled
2. Inject the module (use injector or manual mapping)
3. Enter a match and check if ESP boxes appear around players
4. Test through walls, at distance, in different lighting conditions
5. Verify mouse clicks pass through overlay (WS_EX_TRANSPARENT)

---

## Summary

This knowledge base documents all research, improvements, and technical details for the Apex Legends ESP Overlay project. It serves as a reference for:
1. Current implementation state (Phase 4 complete)
2. Identified improvements with priority levels
3. Offset references and pattern scanning strategies
4. D3D12 overlay best practices
5. Performance optimization techniques
6. Future enhancement roadmap (Phases 5-7)
7. Known issues and workarounds
8. Research sources and quick reference guides

**Next Steps:** Phase 5 - Skeleton ESP + Camera Tracking implementation

---

## 10. Bone Array Structure for Skeleton ESP (NEW)

### Source Engine Bone System Overview
Apex Legends uses the Source engine's bone-based animation system. Each entity that has a model stores bone data in a hierarchical structure accessible through `DT_BaseAnimating`.

### Key Offsets from W3AP/Apex-offsets (Season 30)
| Field | Offset | Type | Description |
|-------|--------|------|-------------|
| `m_nForceBone` | +0xdd0 | int32_t | Force bone index for special animations |
| `m_pStudioHdr` | +0xfd0 / +0x1000* | uint64_t | Pointer to studio model header (contains bone definitions) |
| `studioHdr` | +0x1000 | uint64_t | Studio header pointer (alternate offset) |

### Bone Array Access Pattern
```cpp
// Step 1: Read m_pStudioHdr from entity (+0xfd0 or +0x1000 depending on build)
uint64_t studioHdr = Read<uint64_t>(entityAddress + 0xfd0);

// Step 2: If studioHdr is valid, read bone count and array
// DT_BaseAnimating has m_nForceBone at +0xdd0
int32_t forceBone = Read<int32_t>(entityAddress + 0xdd0);

// Bone positions are typically accessed through the model state
// CModelState structure contains:
// - m_pBones (pointer to bone array)
// - m_nFlags (bone update flags)
```

### Skeleton ESP Bone Chain (Standard Humanoid)
The standard humanoid skeleton has 16-20 bones. For ESP purposes, use the following chain:

| Index | Bone Name | Description |
|-------|-----------|-------------|
| 0 | root / hips | Root of skeleton, approximately pelvis position |
| 1 | spine_01 | Lower spine |
| 2 | spine_02 | Mid spine |
| 3 | spine_03 | Upper spine / chest |
| 4 | neck | Neck joint |
| 5 | head | Head (top of skull) |
| 6 | left_clavicle | Left shoulder |
| 7 | left_upperarm | Left upper arm |
| 8 | left_lowerarm | Left forearm |
| 9 | left_hand | Left hand |
| 10 | right_clavicle | Right shoulder |
| 11 | right_upperarm | Right upper arm |
| 12 | right_lowerarm | Right forearm |
| 13 | right_hand | Right hand |
| 14 | left_thigh | Left upper leg |
| 15 | left_calf | Left lower leg |
| 16 | left_foot | Left foot |
| 17 | right_thigh | Right upper leg |
| 18 | right_calf | Right lower leg |
| 19 | right_foot | Right foot |

### Skeleton Connection Pairs for Line Rendering
```cpp
// Spine chain (core body)
{0,1}, {1,2}, {2,3}

// Neck and head
{3,4}, {4,5}

// Left arm
{6,7}, {7,8}, {8,9}

// Right arm
{10,11}, {11,12}, {12,13}

// Left leg
{0,14}, {14,15}, {15,16}

// Right leg
{0,17}, {17,18}, {18,19}
```

### Bone Position Reading from CModelState
Based on CS2 skeleton ESP patterns (applicable to Source engine):
```cpp
class CModelState {
public:
    char pad_0x0000[0x80];      // Padding before bone data
    void* m_pBones;              // +0x80 - Pointer to bone array
};

struct Bone_t {
    DirectX::XMFLOAT3 position;  // World space position of the bone
    DirectX::XMFLOAT4 rotation;  // Quaternion rotation
    float scale;                 // Scale factor (usually 1.0)
};
```

### Visibility Check for Bones
- Compare `lastVisibleTime` offset (+0x1a94 from W3AP data) with current game time
- If visible: render bone in green
- If hidden behind walls: render bone in red or dimmed color
- This provides additional information about whether the player is peeking

### Implementation Notes for Skeleton ESP
1. **Performance**: Reading all 20 bones per entity = ~480 bytes of memory reads per frame for 64 entities. Consider caching bone data and only updating when entity position changes significantly.
2. **Bone Index Mapping**: Different legends may have slightly different bone counts. Always check `studioHdr->nBones` before reading the array.
3. **Firing Range Dummies**: Skeleton ESP also works on training dummies - they use the same bone structure as players.
4. **Ragdoll State**: When a player is dead, bones may be in ragdoll position (different from standing pose). Check `m_bleedoutState` (+0x27a0) to detect this.

---

## 11. View Matrix and Camera Tracking (NEW)

### Direct View Matrix Offset
From W3AP/Apex-offsets (Season 30):
| Field | Offset | Type | Description |
|-------|--------|------|-------------|
| `ViewMatrix` | +0x11a390 | float[16] | **Direct view matrix** - World-to-screen transformation |

This is the most reliable method for W2S as it provides the complete projection matrix.

### Camera Position Offsets
From multiple sources (W3AP, CheatOffsets):
| Field | Offset | Type | Description |
|-------|--------|------|-------------|
| `camera_origin` | +0x1fcc / +0x1fb4c | XMFLOAT3 | Camera/world position for rendering |
| `camera_angles` | +0x1f5c / +0x22cc | XMFLOAT3 | View angles (yaw, pitch, roll) |

### Camera Tracking from Local Player
From ReactiioN1337 dump:
```ini
CPlayer!camera_origin=0x1f50
CPlayer!camera_angles=0x1f5c
```

**Note:** Offsets vary between builds. Always verify with current game version.

### World-to-Screen Using View Matrix (Recommended)
The view matrix approach is more reliable than manual yaw/pitch calculation:

```cpp
bool WorldToScreen(const DirectX::XMFLOAT3& worldPos, 
                   DirectX::XMFLOAT2& screenPos,
                   const float* viewMatrix,  // 4x4 matrix in row-major order
                   int screenWidth, 
                   int screenHeight) {
    // Transform world position by view matrix
    float w = viewMatrix[3] * worldPos.x + viewMatrix[7] * worldPos.y + 
              viewMatrix[11] * worldPos.z + viewMatrix[15];
    
    if (w < 0.01f) return false; // Behind camera
    
    float x = viewMatrix[0] * worldPos.x + viewMatrix[4] * worldPos.y + 
              viewMatrix[8] * worldPos.z + viewMatrix[12];
    float y = viewMatrix[1] * worldPos.x + viewMatrix[5] * worldPos.y + 
              viewMatrix[9] * worldPos.z + viewMatrix[13];
    
    // Convert to screen space
    screenPos.x = (screenWidth / 2) * (1.0f - x / w);
    screenPos.y = (screenHeight / 2) * (1.0f + y / w);
    
    return true;
}
```

### Camera-Aware W2S Implementation (Current Approach)
The current `CalculateScreenPositionWithCamera` uses:
- Local player view angles (yaw/pitch) for camera direction
- Forward/right/up vectors derived from angles
- Manual projection math

**Improvement:** Replace with direct ViewMatrix reading (+0x11a390) for better accuracy, especially during:
- ADS (aim down sights) - FOV changes
- Sprinting animations
- Jumping/crouching transitions
- Camera shake effects

### FOV Calculation from View Matrix
```cpp
// Extract horizontal FOV from view matrix element [5][5] or projection matrix
float GetFOVFromViewMatrix(const float* viewMatrix) {
    // The FOV is encoded in the projection matrix
    // For Source engine, use: fov = 2 * atan(1.0f / viewMatrix[5][5])
    return 0.0f; // Placeholder - actual formula depends on matrix layout
}
```

### Camera Position vs Entity Position
- **Entity position** (`m_localOrigin` +0x4 or `m_vecAbsOrigin` +0x16c/0x170): World space origin of the entity model
- **Camera position**: Player's eye/camera position for rendering
- For W2S, use camera position as the "eye point" and entity position as the target
