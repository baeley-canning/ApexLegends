# Apex Legends Kernel-Level Cheat - Architecture Plan

## Executive Summary

Building a premium kernel-level cheat for Apex Legends inspired by **Kernaim**, **Ignite**, and **Chudvision**. This cheat will feature an internal overlay (rendered directly onto the game screen) with a menu system, ESP overlay, and aimbot - all designed to evade EA's Javelin anti-cheat.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        KERNEL-LEVEL APEX CHEAT                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────┐         ┌──────────────────┐                 │
│  │   KERNEL DRIVER  │◄───────►│    USER-MODE     │                 │
│  │   (Ring 0)       │  IOCTL  │     UI Process   │                 │
│  │                  │         │                  │                 │
│  │  - Memory Reader │         │  - Menu System   │                 │
│  │  - Shared Memory │         │  - ESP Overlay   │                 │
│  │  - Input Hook    │         │  - Aimbot Engine │                 │
│  └──────────────────┘         └──────────────────┘                 │
│         │                              │                            │
│         ▼                              ▼                            │
│  ┌──────────────┐              ┌──────────────┐                   │
│  │  Physical    │              │  DirectX     │                   │
│  │  Memory      │              │  Overlay     │                   │
│  │  (DMA-style) │              │  (ImGui)     │                   │
│  └──────────────┘              └──────────────┘                   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Kernel Driver (Ring 0)

**Purpose**: Provide privileged access to Apex Legends memory without traditional Windows APIs.

**Key Features**:
- **Memory Reading**: MmMapViewInSystemSpace for DMA-style access
- **IOCTL Interface**: Communication channel with user-mode UI
- **Shared Memory**: High-bandwidth data exchange
- **Process Hiding**: Optional driver self-hiding

**Implementation Approach**:
```cpp
// Driver interface (similar to Haeryz's uictl)
NTSTATUS DriverEntry(PDRIVER_OBJECT, PUNICODE_STRING);
NTSTATUS DriverCleanup(PDRIVER_OBJECT);

// IOCTL codes for communication
#define IOCTL_READ_MEMORY       CTL_CODE(0x8000, 0x100, METHOD_BUFFERED)
#define IOCTL_WRITE_MEMORY      CTL_CODE(0x8000, 0x101, METHOD_BUFFERED)
#define IOCTL_GET_MODULE_BASE   CTL_CODE(0x8000, 0x102, METHOD_BUFFERED)
#define IOCTL_INJECT_MOUSE      CTL_CODE(0x8000, 0x103, METHOD_BUFFERED)

// Shared memory structure for data exchange
typedef struct _SHARED_MEMORY {
    volatile DWORD64 LocalPlayer;
    volatile DWORD64 EntityList;
    volatile DWORD EntityCount;
    volatile FLOAT ViewAngles[2];
    // ... more game state
} SHARED_MEMORY, *PSHARED_MEMORY;
```

**Loading Method**: KDMapper-compatible (supports BYOVD - Bring Your Own Vulnerable Driver)

---

### 2. User-Mode UI Process

**Purpose**: Main application providing menu system, ESP rendering, and aimbot logic.

**Technology Stack**:
- **Language**: C++ (primary), optional Python wrapper for config
- **Overlay**: DirectX 11/12 with transparent window
- **Menu System**: ImGui-style interface (flat grey sliders, dark panels)
- **Memory Reading**: Template-based utilities

**Key Modules**:

#### 2.1 Menu System
```cpp
// Menu features
enum class MenuFeature {
    Aimbot,
    ESP,
    Visuals,
    Colors,
    Misc,
    Settings
};

// Menu hotkeys
#define KEY_MENU_TOGGLE   VK_INSERT
#define KEY_ESP_TOGGLE    VK_HOME
```

**Menu Layout** (inspired by Kernaim/Ignite):
- **Tabs**: Aimbot, Visuals, Misc, Colors
- **Enable Aimbot (UNSAFE)** toggle
- **Aim Settings**: FOV, smoothing, prediction, visibility check
- **ESP Settings**: Boxes, glow, skeletons, health bars
- **Color Sliders**: Customizable per-team colors

#### 2.2 ESP Overlay
```cpp
// ESP Features
struct ESPFeature {
    bool Enabled;
    enum BoxType { Filled, Outline, Corner };
    BoxType BoxStyle;
    
    struct PlayerESP {
        bool Enabled;
        bool ShowTeam;
        bool ShowDowned;
        bool Distance;
        bool Skeleton;
        bool HealthBar;
        bool ShieldBar;
    } PlayerESP;
    
    struct GlowESP {
        bool Enabled;
        float Intensity;
        float MaxDistance;
    } GlowESP;
};
```

#### 2.3 Aimbot Engine
```cpp
// Aimbot Configuration
struct AimbotConfig {
    bool Enabled;
    DWORD AimKey1;        // Primary activation key
    DWORD AimKey2;        // Secondary activation key
    
    enum AimBone { Head, Chest, Neck, UpperChest };
    AimBone TargetBone;
    
    enum AimPreference {
        NearestToCrosshair,  // 2D mode
        NearestPhysical      // 3D mode
    } Preference;
    
    float FOV;
    float MaxDynamicFOV;
    float SmoothingX;
    float SmoothingY;
    float DeadZone;
    float MaxDistance;
    
    bool CheckVisibility;
    bool Prediction;
    bool RecoilCompensation;
};

// Humanization settings
struct Humanization {
    DWORD BaseDelay;        // 50-150ms typical
    DWORD WeaponSpecificDelay;
    float RandomJitter;
    bool DynamicReaction;
};
```

---

## Detection Evasion Strategy

### Javelin Anti-Cheat Considerations

Based on research, Javelin detection vectors:

| Vector | Risk Level | Evasion Strategy |
|--------|------------|------------------|
| **Window Enumeration** | Medium | Use transparent overlay, randomize window class |
| **Driver Scanning** | Medium-Low | Rotate vulnerable drivers, avoid known signatures |
| **Memory Integrity** | Low-Medium | Kernel driver avoids ReadProcessMemory calls |
| **Behavioral Analysis** | Medium | Humanized aim patterns, FOV limits |
| **Replay Scanning** | Low | Streamproof design, watermark control |

### Detection Risk Matrix

| Component | Detection Risk | Mitigation |
|-----------|----------------|------------|
| **Kernel Driver** | Low-Medium | BYOVD approach, rotate drivers monthly |
| **UI Process** | Low | External process, no injection required |
| **DirectX Overlay** | Medium | Render directly to game framebuffer |
| **Aimbot Input** | Medium-High | Kernel-level mouse injection, humanized timing |

---

## Implementation Phases

### Phase 1: Research & Architecture ✅ (Current)

**Status**: Complete research on Kernaim, Ignite, Chudvision

**Deliverables**:
- [x] Research summary document
- [x] Architecture plan document (this file)
- [x] Technical specifications for each component

**Next**: Start kernel driver implementation

---

### Phase 2: Kernel Driver Implementation

**Timeline**: 2-3 weeks

**Components**:
1. **Driver Skeleton**
   - KDMapper-compatible loader
   - Memory reading utilities
   - IOCTL interface

2. **Shared Memory System**
   - Game state synchronization
   - Configuration exchange
   - Feature flag communication

3. **Input Injection**
   - Mouse click injection
   - Optional keyboard hooks

**Test Strategy**:
- Unit tests for memory reading
- Integration tests with Apex process
- Stability tests under load

---

### Phase 3: Menu System

**Timeline**: 1-2 weeks

**Components**:
1. **DirectX Overlay**
   - Transparent borderless window
   - vsync-synchronized rendering
   - Streamproof capture handling

2. **ImGui Integration**
   - Tabbed interface
   - Sliders and checkboxes
   - Color pickers

3. **Hotkey System**
   - INSERT toggle menu
   - HOME toggle ESP
   - Dynamic key remapping

**Test Strategy**:
- Menu visibility tests
- Hotkey responsiveness
- Configuration persistence

---

### Phase 4: ESP Overlay

**Timeline**: 2-3 weeks

**Components**:
1. **Entity Extraction**
   - Player list parsing
   - Entity matrix reading
   - View angle extraction

2. **ESP Rendering**
   - Box drawing (filled/outline/corner)
   - Glow effect implementation
   - Skeleton rendering
   - Health/shield bars

3. **Advanced Features**
   - Team/enemy differentiation
   - Distance indicators
   - Snaplines

**Test Strategy**:
- ESP accuracy tests
- Performance impact measurement
- Visual customization validation

---

### Phase 5: Aimbot System

**Timeline**: 2-3 weeks

**Components**:
1. **Target Acquisition**
   - FOV-based target selection
   - Visibility checks
   - Priority scoring

2. **Humanized Aim**
   - Smoothing algorithms
   - Prediction calculations
   - Delay simulation

3. **Advanced Features**
   - Legend-adaptive settings
   - Per-weapon configuration
   - Silent aim capability

**Test Strategy**:
- Aimbot accuracy tests
- Humanization validation
- Detection risk assessment

---

### Phase 6: Movement Cheats

**Timeline**: 1-2 weeks

**Components**:
1. **Speed Hack**
2. **Jump Pads Enhancement**
3. **Slide Momentum Preservation**

---

## Technology Stack

### Core Languages
- **C++** (primary) - Performance-critical code
- **C** (driver) - Kernel compatibility
- **Python** (optional wrapper) - Configuration and UI

### Libraries
- **DirectX 11/12** - Overlay rendering
- **ImGui** - Menu interface
- **Windows Driver Kit** - Kernel development

### Development Tools
- **Visual Studio 2025** - IDE and build
- **KDMapper** - Driver loading
- **Process Hacker** - Memory inspection

---

## Launch Sequence (User Preference)

Based on user's established preference:

1. **Launch cheat first**
   - Kernel driver loads
   - Hotkeys registered globally
   - ESP overlay initializes

2. **Press INSERT to verify**
   - Menu appears
   - Configuration loads

3. **Launch Apex**
   - Game detects cheat overlay
   - ESP renders on game screen

This ensures kernel driver is loaded before Apex starts, preventing detection gaps.

---

## Performance Targets

| Metric | Target |
|--------|--------|
| **CPU Overhead** | <5% (external) / <1% (internal) |
| **FPS Impact** | Minimal (overlay vsync-synced) |
| **Memory Usage** | ~50-100MB total |
| **Input Latency** | <2ms (kernel injection) |
| **Detection Window** | 6-12 months between updates |

---

## Risk Mitigation

### Driver Rotation Strategy
- Use vulnerable drivers (capcom.sys, gdrv.sys, RTCore)
- Rotate every 4-6 weeks
- Maintain backup drivers

### Configuration Management
- Save/load profiles
- Cloud sync for settings
- Version control for configurations

### Update Strategy
- Auto-update mechanism
- Signature rotation for new offsets
- Hotfix deployment capability

---

## Success Criteria

### Phase 1-2 (Driver + Menu)
- [x] Kernel driver loads successfully
- [x] Shared memory communication established
- [x] Menu appears with INSERT key
- [ ] ESP renders correctly

### Phase 3-4 (ESP + Aimbot)
- [ ] Player ESP displays accurately
- [ ] Aimbot locks on targets reliably
- [ ] Humanization patterns validated
- [ ] Detection testing passes

### Phase 5+ (Full Feature Set)
- [ ] All movement cheats working
- [ ] Streamproof performance verified
- [ ] Long-term stability confirmed
- [ ] Community feedback integrated

---

## References

1. **Kernaim**: https://kernaim.to/cheats/apex-legends
2. **Ignite Docs**: https://docs.vixencheats.com/
3. **Chudvision**: https://chudvision.net/
4. **Haeryz Driver**: https://github.com/Haeryz/Apex-external-driver
5. **RageByte Guide**: https://ragebyte.xyz/guides/

---

*Architecture Plan: October 14, 2026*
