# Reverse Engineering - Apex Legends & Javelin Anti-Cheat

**For:** Next developer/assistant  
**Last Updated:** October 14, 2026  
**Project Location:** `C:\Users\New User\OneDrive\Desktop\QwenKern\`

---

## Apex Legends Analysis

### Game Information
- **Main Executable:** `r5apex_dx12.exe`
- **Game Version:** v3.0.3.65 (CL11630615)
- **Build String:** R5pc_r5-301_J65_CL11630615_FSv30_1_2026_10_02_09_54
- **Developer:** Respawn Entertainment
- **Publisher:** Electronic Arts

### Launch Configuration
**Launch Script:** `launchBuildClient.bat`
```batch
start start_protected_game.exe -anticheat_settings=Settings.json -noautopak +errorHud_enabled 0 -nop4 +net_showchoke 1 -shipsound -originForceupToDate
```

**Key Launch Parameters:**
- `-anticheat_settings=Settings.json` - Javelin configuration
- `-noautopak` - Disable automatic pak loading
- `+errorHud_enabled 0` - Disable error HUD
- `-nop4` - Disable P4 (likely P4 profiling or telemetry)
- `+net_showchoke 1` - Enable network choke visualization
- `-shipsound` - Ship sound configuration
- `-originForceupToDate` - Force Origin to latest version

---

## EA Javelin Anti-Cheat Components

### Core Executables (Root Level)

#### EAAntiCheat.GameServiceLauncher.exe
- **Version:** 1.0.48125.0 (Build 48125)
- **Product Version:** 1.0.15973373
- **Description:** EA Javelin Anticheat
- **Internal Name:** skyfall
- **Company:** El

#### start_protected_game.exe
- Wrapper executable for protected game launch
- Handles Javelin initialization before game starts

---

## Javelin Architecture

### User-mode Agent + Kernel Driver
- Javelin runs at Ring 0 (kernel level) alongside the Windows kernel
- Can inspect other processes' memory, watch driver loads, monitor handle access
- Blocks/terminates suspicious activity before user-mode anti-cheat could detect it

### EASPEAR Layer (Online Services)
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

## 7 Detection Categories

| Category | Risk Level | Evasion Strategy |
|----------|------------|------------------|
| Signature Scanning | Medium-High | Code obfuscation, MBA folding |
| Behavioral Analysis | High | Humanizer pipeline, rank-matched profiles |
| Machine Learning | High | Telemetry obfuscation, pattern alignment |
| Heuristic Detection | Medium | Clean injection methods, minimal hooks |
| Hardware Fingerprinting | Medium-Low | TPM integration, hardware randomization |
| Kernel-Mode Scanning | High | Kernel driver with stealth techniques |
| Server-Side Validation | Medium | Telemetry alignment with human baselines |

---

## Key Statistics (Sep 2026)
- **Games protected:** 20 titles
- **Players safeguarded:** 57.1 million
- **Cheat attempts flagged:** 26.7 million
- **Detection accuracy:** >99%
- **Error rate:** <1%

---

## Match Infection Rate (MIR) System

**Definition:** Tracks both CONFIRMED AND SUSPECTED cheaters, measuring confidence that at least one cheater impacted any given match.

**Key Metrics:**
- MIR increased from 2.28% to 3.09% in January 2026
- Post-launch MIR: ~2% (98% of matches fair and clean)
- "Stealth cheats" (avoiding "high impact") cause MIR to rise

**New Ban Acceleration (Deployed Jan 26, 2026):**
- Impacts MIR calculations
- Includes suspected cheaters in ban waves
- Refines detection signals continuously

---

## Three-Step Enforcement Process

1. **PREVENT** cheating when possible (block before function)
2. **DETECT** when it gets through
3. **ACT** with evidence-based enforcement

**Key Insight:** Prevention ≠ Bans
- 265,550 prevented attempts in Apex week one
- Only 12,969 bans (many stopped before ban threshold)

---

## External Cheats Can Be Undetected

**Key EA Quotes (Sep 2026):**
> "We operate at kernel level because detecting external cheats requires it, not because we want deeper access."

> "Javelin only runs when a game with Javelin protection included is running."

> "Cheat providers often advertise 'undetectable' status, a claim that's always temporary."

**External Cheat Advantages:**
- Don't interact with game process directly
- Can operate at kernel level (separate from game)
- External overlays don't inject into game memory
- Javelin auto-uninstalls when no EA games present

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

## Implementation Status

### Phase 2: Kernel Driver ✅ COMPLETE
- Complete C++ kernel driver with all detection category coverage
- 16 C/C++ files in `phase2_kernel_driver/`

### Phase 3: Menu System (In Progress)
- C++/ImGui core with DirectX overlay
- Matching Kernaim/Ignite/Chudvision UI patterns

### Phase 4: ESP Overlay (In Progress)
- Entity extraction and rendering
- Dynamic ESP configuration

---

## Research Files Location

**Qwen Knowledge Base:** `C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\`

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

## Key Takeaways for Cheat Development

1. **Launch Order Matters** - Cheat first, then Apex for kernel-level injection
2. **Internal Overlay Preferred** - Render directly onto game via D3D hooks
3. **Hotkeys Should Be Global** - INSERT=menu, HOME=ESP
4. **Shared Memory IPC** - Use `Global\ApexCheatMenuData` for menu-driver communication
5. **Javelin Detection Categories** - Cover all 7 categories in implementation

---

## Files to Review

### QwenKern Root
- `JAVELIN_RESEARCH_COMPLETE.md` - Javelin overview
- `Javelin Anti-Cheat Research 2026.txt` - Full research document
- `Javelin Behavioral Biometrics & Humanizer Pipeline.txt` - Human baseline patterns

### phase3_javelin_reports/
- `signature_scanning_report.md`
- `behavioral_analysis_report.md`
- `ml_detection_report.md`
- `kernel_mode_scanning_report.md`
- `heuristic_detection_report.md`
- `hardware_fingerprinting_report.md`
- `server_side_validation_report.md`
- `EVASION_OPPORTUNITY_MATRIX.md`

### javelin_research_agents/
- `Detection_Patterns_Research.txt`
- `Griffin_VM_Research.txt`
- `KDMapper_Research.txt`
- `Low-Level_Detection_Cheat_Architecture.txt`
- `Telemetry_EASPEAR_Research.txt`

---

**Status:** Comprehensive reverse engineering complete. Ready for Phase 3-4 implementation.
