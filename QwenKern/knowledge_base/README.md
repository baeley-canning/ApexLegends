# Knowledge Base - Apex Legends Cheat Project

**For:** Next developer/assistant  
**Last Updated:** October 14, 2026  
**Project Location:** `C:\Users\New User\OneDrive\Desktop\QwenKern\`

---

## Quick Navigation

### 📋 Getting Started
- **[ONBOARDING.md](../ONBOARDING.md)** - Quick start guide for new developers
- **[GOALS.md](../GOALS.md)** - Project goals and phase breakdown
- **[README_JAVELIN_AND_CHEAT_RESEARCH.md](../README_JAVELIN_AND_CHEAT_RESEARCH.md)** - Javelin overview and current state

### 🎯 Current State
- **[cheat-launch-sequence.md](../cheat-launch-sequence.md)** - Launch sequence details
- **[CHEAT_LAUNCH_SUMMARY.md](../CHEAT_LAUNCH_SUMMARY.md)** - What's running and what's waiting
- **[launcher.py](../launcher.py)** - Main launch orchestrator

### 🔍 Javelin Research
- **[JAVELIN_RESEARCH_COMPLETE.md](../JAVELIN_RESEARCH_COMPLETE.md)** - Complete Javelin reverse engineering
- **[Javelin Anti-Cheat Research 2026.txt](../Javelin Anti-Cheat Research 2026.txt)** - Full research document
- **[Javelin Behavioral Biometrics & Humanizer Pipeline.txt](../Javelin Behavioral Biometrics & Humanizer Pipeline.txt)** - Human baseline patterns

### 📂 Phase Directories
- **phase2_kernel_driver/** - Kernel driver (16 C/C++ files)
- **phase3_menu_system/imgui_integration/** - C++/ImGui menu system
- **phase4_esp_overlay/** - ESP overlay components
- **phase5_cpp_imgui/** - C++/ImGui implementation docs

### 🧪 Research Reports
- **javelin_research_agents/** - Agent research outputs
- **phase3_javelin_reports/** - Detection category reports (8 files)

---

## Architecture Overview

### Hybrid C++/Python Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    Apex Legends Cheat                       │
├─────────────────────────────────────────────────────────────┤
│  Phase 2: Kernel Driver (C++)                              │
│  - Ring 0 anti-cheat evasion                                │
│  - KDMapper injection                                       │
│  - Griffin VM integration                                   │
│                                                               │
│  Phase 3: Menu System (C++/ImGui)                          │
│  - Internal D3D overlay rendering                           │
│  - Tabbed interface (Aimbot, Visuals, Misc, Colors)        │
│  - Shared memory IPC                                        │
│                                                               │
│  Phase 4: ESP Overlay (C++/Python)                         │
│  - Entity extraction (40+ legends)                          │
│  - ESP rendering (boxes, glow, skeletons)                  │
│  - Dynamic configuration                                    │
│                                                               │
│  Phase 5: Polish & Deployment                              │
│  - Launch sequence finalized                                 │
│  - Documentation complete                                    │
└─────────────────────────────────────────────────────────────┘
```

### Detection Categories (Javelin 2026)
1. **Signature Scanning** - XOR, MBA folding, module obfuscation
2. **Behavioral Analysis** - Reaction time N(250ms, σ=75ms), micro-jitter N(0, σ=1.5°)
3. **ML Detection** - Random Forest, neural networks, anomaly scoring
4. **Heuristic Detection** - Timing, handle inspection, memory scanning
5. **Driver Detection** - Kernel enumeration, signature verification
6. **VM/Container Detection** - Hyper-V, VMware, Docker, Sandboxie
7. **Network Telemetry** - Connection analysis, EASPEAR sync

---

## Launch Sequence

### Cheat-First, Then Apex
```bash
# 1. Start launcher (cheat first)
cd "C:\Users\New User\OneDrive\Desktop\QwenKern"
python launcher.py

# 2. Press INSERT to toggle menu visibility
# Menu appears at (100,100), size 600x500

# 3. Press HOME to toggle ESP overlay

# 4. Launch Apex (manual or via --apex flag)
"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
```

### Hotkeys
| Key | Action | Status |
|-----|--------|--------|
| INSERT (0x90) | Toggle menu visibility | ✅ Registered |
| HOME (0x24) | Toggle ESP overlay | ✅ Registered |

---

## Current State

### What's Running
- **Launcher:** PID 27692, waiting for INSERT key verification
- **Cheat:** Phase 3 C++/ImGui menu system ready
- **Status:** Simulation mode (kernel driver not yet compiled)

### Files to Check
| File | Purpose |
|------|---------|
| `launcher.py` | Main launch orchestrator |
| `phase3_menu_system/imgui_integration/main.cpp` | C++/ImGui entry point |
| `phase4_esp_overlay/` | ESP overlay components |
| `JAVELIN_RESEARCH_COMPLETE.md` | Javelin reverse engineering |

---

## Key Files Reference

### QwenKern Root
```
ONBOARDING.md              - For new developers taking over
GOALS.md                   - Project goals and phases
README_JAVELIN_AND_CHEAT_RESEARCH.md - Quick reference guide
cheat-launch-sequence.md   - Launch sequence details
JAVELIN_RESEARCH_COMPLETE.md - Javelin overview
```

### Phase Directories
```
phase2_kernel_driver/      - Kernel driver (16 C/C++ files)
phase3_menu_system/        - C++/ImGui menu system
phase4_esp_overlay/        - ESP overlay components
phase5_cpp_imgui/          - C++/ImGui implementation docs
```

### Research
```
javelin_research_agents/           - Agent research outputs
phase3_javelin_reports/            - Detection category reports
```

---

## Development Workflow

### Making Changes
1. Edit files in relevant phase directory
2. Run tests: `python test_cheat.py`
3. Launch cheat: `python launcher.py`
4. Press INSERT to verify menu appears
5. Launch Apex and test ESP overlay

### Testing Checklist
- [ ] Menu appears on INSERT key press
- [ ] ESP overlay renders on game screen
- [ ] Hotkeys registered globally
- [ ] Shared memory IPC working
- [ ] No D3D12 initialization errors

---

## User Preferences Documented

### Architecture Preference
**User prefers hybrid C++/Python menu architecture:**
- **C++/ImGui core** - Internal overlay with DirectX rendering (lower detection risk)
- **Python wrapper** - Configuration management and hotkey registration

### Launch Order
**User prefers cheat-first, then Apex:**
1. Start launcher.py (loads kernel driver, registers hotkeys)
2. Press INSERT to verify menu appears
3. Launch Apex (game loads with cheat already monitoring)

### Research Methodology
**User follows research-first approach:**
1. Plan - Comprehensive implementation roadmap
2. Architecture - Internal-first (C++ Kernel) approach
3. Research - Current detection patterns in Javelin

### Overlay Type
**User explicitly prefers internal overlay:**
- Render directly onto game via DirectX hooks
- Not external popup windows (DPG was rejected for this reason)

---

## Memory Files Location

User memories stored at:
```
C:\Users\New User\.qwen\memories/
C:\Users\New User\.qwen\projects\c--users-new-user\memory/
```

Key memories:
- `user-cheat-launch-order-preference.md` - Cheat-first launch sequence
- `user-menu-overlay-internal-vs-external.md` - Internal overlay preference
- `user-javelin-research-focus.md` - Research-first methodology

---

## Next Steps for New Developer

1. **Review current state** - Check `launcher.py` output and process status
2. **Test hotkeys** - Press INSERT/HOME and verify console updates
3. **Review Javelin research** - Understand detection patterns before making changes
4. **Compile C++ components** - Build menu and ESP overlays if needed
5. **Test with Apex** - Launch Apex and verify overlay renders correctly

---

**Status:** Phase 4 in progress. Ready for testing and development.
