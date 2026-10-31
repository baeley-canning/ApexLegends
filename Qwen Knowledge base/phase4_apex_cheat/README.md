# Phase 4 Cheat - Legacy Directory

**Status:** 📦 ARCHIVED  
**Production Version:** `phase4_apex_cheat_package/`  
**Last Updated:** October 14, 2026

---

## Overview

This directory contains **legacy Phase 4 implementations** that have been consolidated into the production `phase4_apex_cheat_package/`.

### Directory Structure

```
phase4_apex_cheat/
├── archive/              # Archived legacy files (see below)
│   ├── legacy_*.py       # Legacy Python scripts
│   ├── legacy_*.md       # Legacy documentation
│   └── legacy_cheat_core/# Legacy cheat core module
├── requirements.txt      # Dependencies (keep for reference)
└── README.md            # This file
```

### Archived Legacy Files

**Menu Implementations:**
- `legacy_external_menu.py` - Tkinter menu (replaced by DPG in package)
- `legacy_dpg_subprocess.py` - DPG subprocess (in package now)
- `legacy_imgui_menu.py` - ImGui menu (replaced by DPG)
- `legacy_minimal_menu.py` - Minimal menu alternative

**Launcher Scripts:**
- `legacy_launcher.py` - Main launch script
- `legacy_launch_phase4.py` - Phase 4 launcher variant
- `legacy_main.py` - Main entry point
- `legacy_launch_subprocess.py` - Subprocess launcher

**Test Files:**
- `legacy_test_memory_hooks.py` - Memory hook tests
- `legacy_test_pack_duplication.py` - Pack duplication tests
- `legacy_apex_pack_dupe.py` - Hybrid dup script

**Apex Pack Features:**
- `legacy_apex_pack_network.py` - Network monitoring
- `legacy_vm_deploy.py` - VM deployment script
- `legacy_vm_exclude.txt` - VM exclusion rules

---

## Production Version

**Use `phase4_apex_cheat_package/` for production:**

```
phase4_apex_cheat_package/
├── apex_cheat.dll          # Main DLL (41,984 bytes)
├── launcher.py             # Launch script (production)
├── apex_cheat_py.py        # Python wrapper
├── cheat_menu.py           # DPG menu implementation
├── tests/                  # Test suite (10/10 passing)
└── source/                 # C++ source files
```

### Why Archive This Directory?

This legacy directory contains:
- **Early experiments** - Tkinter, ImGui, minimal menu variants
- **Pack duplication research** - Apex Pack hybrid duplication
- **VM deployment scripts** - VM-specific configurations
- **Network captures** - PCAP files from testing

All these features have been refined and moved to the production package.

---

## Knowledge Base Integration

This directory is part of the **Qwen Knowledge Base** project:

```
Qwen Knowledge base/
├── phase4_apex_cheat/              # 📦 ARCHIVE (legacy)
├── phase4_apex_cheat_package/      # ✅ PRODUCTION
├── phase5_cpp_ImGui/               # 🚧 PHASE 5 (in progress)
└── *.txt files                      # Knowledge base docs
```

---

## Next Steps

1. **Review archived files** - Check `archive/` for any remaining needs
2. **Use production package** - `phase4_apex_cheat_package/` is the main version
3. **Monitor Phase 5** - C++ ImGui implementation in progress

---

*Legacy Phase 4 Directory - Updated October 14, 2026*
