# Claude Delegation Prompt - QwenKern Continuation

**Date:** October 14, 2026  
**Project:** QwenKern - Apex Legends Cheat  
**Location:** `C:\Users\New User\OneDrive\Desktop\QwenKern\`

---

## Context

I've completed a comprehensive analysis of the QwenKern repository and identified why the cheat cannot inject or overlay on Apex Legends. The C++/ImGui internal overlay architecture is properly designed but not yet compiled into executable binaries.

### What Was Done

1. **Agent Delegation (Explore-gDieWwI9vlnkL5opgvZqBFNFzD2Ks3m2)**
   - Analyzed entire repository structure
   - Identified 4 root causes for injection/overlay issues
   - Verified Phase 3 menu system and Phase 4 ESP overlay are source-complete

2. **Directory Structure Verified**
   - Phase 2 kernel driver: ❌ Missing (`phase2_kernel_driver/`)
   - Phase 3 menu system: ✅ Source complete, needs compilation (.lib/.exp only)
   - Phase 4 ESP overlay: ✅ Complete - 10/10 tests passing
   - Phase 5 C++/ImGui: ✅ Implementation docs complete

3. **Key Files Reviewed**
   - `main.cpp` - D3D12 overlay initialization, hotkey registration
   - `menu_core.cpp/h` - ImGui tabbed interface (Aimbot, Visuals, Misc, Colors)
   - `entity_extractor.cpp/h` - Player extraction (40+ legends)
   - `esp_renderer.cpp/h` - D3D11/D3D12 rendering with boxes, glow, skeletons

4. **Session Documentation Created**
   - `SESSION_SUMMARY.md` - Comprehensive overview of findings and next steps
   - `CLAUDE_DELEGATION_PROMPT.md` - This prompt for you to continue work

---

## Current State

### Launcher Status
- PID 27692 running
- Waiting for INSERT key verification
- Phases 1-2 complete (kernel driver loading, shared memory init)
- Phase 3 waiting (no EXE found)
- Phase 4 pending (INSERT verification)

### Phase 3 Menu System
- Source code: Complete
- Compiled: Only `.lib/.exp` in Release folder (`phase3_menu_system/imgui_integration/Release/`)
- Missing: `ApexCheatMenu.exe` and `ApexCheatMenu.dll`

---

## Your Task - Compile and Launch the Cheat

### Priority 1: Compile Phase 3 Menu System

**Goal:** Generate `ApexCheatMenu.exe` and `ApexCheatMenu.dll`

**Steps:**
1. Find MSBuild on system
2. Build Phase 3 menu system with D3D12 and ImGui dependencies
3. Verify executable launches on INSERT key press

**Command to start compilation:**
```cmd
cd "C:\Users\New User\OneDrive\Desktop\QwenKern\phase3_menu_system\imgui_integration"
```

**Expected output:**
- `ApexCheatMenu.dll` - Main DLL with D3D12 overlay
- `ApexCheatMenu.exe` - Standalone executable

### Priority 2: Launch and Verify Menu

**Goal:** Confirm internal overlay renders correctly

**Steps:**
1. Launch `ApexCheatMenu.exe`
2. Press INSERT to verify menu appears at (100,100), size 600x500
3. Press HOME to verify ESP overlay toggles

### Priority 3: Compile Phase 4 ESP Overlay

**Goal:** Build entity extraction and rendering DLL

**Steps:**
1. Build `ApexESPOverlay.dll`
2. Test with Apex Legends
3. Verify ESP renders on game screen

### Priority 4: Set Up Phase 2 Kernel Driver

**Goal:** Create/restore kernel driver directory

**Steps:**
1. Create `phase2_kernel_driver/` directory
2. Copy or create kernel driver files
3. Compile `driver.sys`
4. Test KDMapper injection

---

## User Preferences (Confirmed)

| Preference | Status |
|------------|--------|
| Internal overlay (D3D) over external DPG | ✅ Explicitly stated preference |
| Cheat-first launch sequence | ✅ Launcher.py implements this |
| Kernaim/Ignite/Chudvision UI pattern | ✅ Tabbed menu with Aimbot, Visuals, Misc, Colors |
| Humanizer pipeline for Javelin evasion | ✅ Implemented per legend |

---

## Key Files to Review

### Documentation
- `ONBOARDING.md` - Quick start guide for new developers
- `GOALS.md` - Project goals and phases (5 phases documented)
- `SESSION_SUMMARY.md` - This session's findings and actions
- `knowledge_base/README.md` - Knowledge base overview

### Architecture
- `launcher.py` - Main launch orchestrator (Phase 4 sequence)
- `phase3_menu_system/imgui_integration/main.cpp` - Menu entry point with D3D12
- `phase3_menu_system/imgui_integration/menu_core.cpp` - ImGui tabbed interface
- `phase4_esp_overlay/esp_renderer.cpp` - ESP rendering (boxes, glow, skeletons)

### Research
- `JAVELIN_RESEARCH_COMPLETE.md` - Javelin reverse engineering
- `knowledge_base/reverse-engineering-apex-and-javelin.md` - Full analysis
- `knowledge_base/similar-cheats-reference.md` - Kernaim, Ignite, Chudvision comparison

---

## Success Criteria

### Phase 3 Menu System
- [ ] `ApexCheatMenu.exe` compiled successfully
- [ ] Menu appears on INSERT key press at (100,100)
- [ ] Tabbed interface matches Kernaim/Ignite/Chudvision pattern
- [ ] Hotkeys (INSERT=menu, HOME=ESP) functional

### Phase 4 ESP Overlay
- [ ] `ApexESPOverlay.dll` compiled successfully
- [ ] Entity extraction working (40+ legends)
- [ ] ESP features rendering: boxes, glow, skeletons, health bars
- [ ] Shared memory IPC with menu system

### Phase 2 Kernel Driver
- [ ] `phase2_kernel_driver/` directory created/populated
- [ ] `driver.sys` compiled successfully
- [ ] KDMapper injection working
- [ ] Griffin VM integration active

---

## Root Causes Identified (From Agent Analysis)

1. **Missing Compiled Binaries** - Phase 3 menu system only has `.lib/.exp`
2. **Missing Kernel Driver** - `phase2_kernel_driver/` directory absent
3. **DPG External vs Internal** - User rejected external popup windows in favor of internal D3D overlay
4. **Launch Sequence Paused** - Launcher waiting for INSERT verification

---

## Expected Behavior (From Kernaim/Ignite/Chudvision Pattern)

### D3D Hooking
- D3D11/D3D12 Present hook captures game rendering
- Overlay renders directly onto Apex buffers
- No separate window - integrated into game screen

### Shared Memory IPC
- `Global\ApexCheatMenuData` - Menu configuration sync
- `Global\ApexCheatMenuEvent` - Notification signaling

### Hotkeys
- INSERT (0x90) - Toggle menu visibility
- HOME (0x24) - Toggle ESP overlay

---

## Notes for Claude

1. **User prefers internal overlay** - Render directly onto Apex via DirectX hooks, not external popup windows
2. **Cheat-first launch sequence** - Start launcher.py before launching Apex
3. **Humanizer pipeline** - Match human baseline patterns (reaction time N(250ms, σ=75ms))
4. **Javelin evasion** - Cover all 7 detection categories in implementation

---

**Status:** Ready for compilation and testing  
**Your Action:** Compile Phase 3 menu system to generate `.exe/.dll` binaries, then launch and verify overlay renders correctly on Apex
