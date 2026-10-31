# EA Javelin Anti-Cheat - Complete Reverse Engineering

## Overview

**EA Javelin** (internal: EAAC) is EA's in-house kernel-level anti-cheat that replaced Easy Anti-Cheat for Apex Legends and now protects 20+ games.

### Key Statistics (as of September 2026)
- **Games protected**: 20 titles
- **Players safeguarded**: 57.1 million
- **Cheat attempts flagged**: 26.7 million
- **Detection accuracy**: >99%
- **Error rate**: <1%

---

## Architecture

### Core Components

#### 1. User-mode Agent + Kernel Driver
- Javelin runs at Ring 0 (kernel level) alongside the Windows kernel
- Can inspect other processes' memory, watch driver loads, monitor handle access
- Blocks/terminates suspicious activity before user-mode anti-cheat could detect it

#### 2. EASPEAR Layer (Online Services)
- Online anti-cheat services for ban enforcement
- Configurable poll interval (default: 60 seconds)
- Ban action strategies: wait_and_retry, immediate_retry, etc.

---

## Griffin VM - The Core Obfuscator

Griffin is a **bin-to-bin (b2b) virtualizer** that transforms native code into virtual machine bytecode.

### Key Characteristics
- Creates new section to store virtualized code
- No handlers (unlike VMP/Themida)
- No virtual stack
- Uses Remill-style lifting for instruction semantics

---

## Detection Categories (7 Total)

### 1. Signature Scanning
- **XOR encryption patterns** - Detect encrypted cheat modules
- **MBA folding** - Algebraic expressions to obfuscate signatures
- **Module obfuscation** - Pattern matching on injected DLLs

### 2. Behavioral Analysis
- **Reaction time profiling** - N(250ms, σ=75ms) human baseline
- **Micro-jitter analysis** - N(0, σ=1.5°) for mouse movements
- **Kill-streak decay** - τ≈10 for detection decay after actions

### 3. ML Detection
- **Random Forest classifiers** - Feature-based detection
- **Neural networks** - Sequence-based behavior analysis
- **Anomaly scoring** - Deviation from baseline patterns

### 4. Heuristic Patterns
- **Timing analysis** - Frame timing anomalies
- **Handle inspection** - Process handle access patterns
- **Memory scanning** - Pattern matching in process memory

### 5. Driver Detection
- **Kernel driver enumeration** - List loaded drivers
- **Driver signature verification** - Check driver signatures
- **Driver behavior monitoring** - Watch driver actions

### 6. VM/Container Detection
- **Virtualization detection** - Hyper-V, VMware, etc.
- **Container detection** - Docker, Sandboxie, etc.
- **VM escape detection** - Detect hypervisor presence

### 7. Network Telemetry
- **Connection analysis** - Outbound connection patterns
- **Traffic analysis** - Packet timing and content
- **EASPEAR communication** - Online anti-cheat sync

---

## Apex Launch Configuration

### launchBuildClient.bat
```batch
start start_protected_game.exe -anticheat_settings=Settings.json -noautopak +errorHud_enabled 0 -nop4 +net_showchoke 1 -shipsound -originForceupToDate
```

### Key Launch Parameters
- `-anticheat_settings=Settings.json` - Javelin configuration
- `-noautopak` - Disable automatic pak loading
- `+errorHud_enabled 0` - Disable error HUD
- `-nop4` - Disable P4 (profiling/telemetry)
- `+net_showchoke 1` - Enable network choke visualization
- `-shipsound` - Ship sound configuration
- `-originForceupToDate` - Force Origin to latest version

---

## Core Executables (Root Level)

### EAAntiCheat.GameServiceLauncher.exe
- **Version**: 1.0.48125.0 (Build 48125)
- **Product Version**: 1.0.15973373
- **Description**: EA Javelin Anticheat
- **Internal Name**: skyfall
- **Company**: El

### start_protected_game.exe
- Wrapper executable for protected game launch
- Handles Javelin initialization before game starts

---

## Evasion Opportunities

### Signature-Based Evasion
1. **XOR encryption** - Encrypt cheat modules with custom keys
2. **MBA folding** - Use Mixed Boolean-Arithmetic expressions
3. **Module renaming** - Rename DLLs to match legitimate signatures

### Behavioral Evasion
1. **Humanizer pipeline** - Add realistic reaction time jitter
2. **Micro-jitter injection** - Simulate human micro-movements
3. **Kill-streak decay** - Space actions to avoid detection spikes

### ML Evasion
1. **Feature spoofing** - Match training feature distributions
2. **Anomaly masking** - Keep anomaly scores below thresholds
3. **Sequence alignment** - Match expected action sequences

---

## Research Files Location

**Qwen Knowledge Base**: `C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\`

### Javelin Research Agents/
- `Detection_Patterns_Research.txt` (10.3 KB)
- `Griffin_VM_Research.txt` (6.1 KB)
- `KDMapper_Research.txt` (4.6 KB)
- `Low-Level_Detection_Cheat_Architecture.txt` (11.3 KB)
- `Telemetry_EASPEAR_Research.txt` (16.0 KB)

### phase3_javelin_research/
- Detection category deep dive analysis
- Evasion pattern research

---

## Implementation Status

### Phase 2: Kernel Driver ✓
- Complete C++ kernel driver with all detection category coverage
- 16 C/C++ files in `phase2_kernel_driver/`

### Phase 3: Menu System (In Progress)
- C++/ImGui core with DirectX overlay
- Matching Kernaim/Ignite/Chudvision UI patterns

### Phase 4: ESP Overlay (In Progress)
- Entity extraction and rendering
- Dynamic ESP configuration

---

## Key Takeaways for Cheat Development

1. **Launch Order Matters** - Cheat first, then Apex for kernel-level injection
2. **Internal Overlay Preferred** - Render directly onto game via D3D hooks
3. **Hotkeys Should Be Global** - INSERT=menu, HOME=ESP
4. **Shared Memory IPC** - Use `Global\ApexCheatMenuData` for menu-driver communication
5. **Javelin Detection Categories** - Cover all 7 categories in implementation
