# Phase 4 Legacy Archive

**Date:** October 14, 2026  
**Purpose:** Archive obsolete files from `phase4_apex_cheat/` that are now superseded by `phase4_apex_cheat_package/`

---

## Files to Archive

### Legacy Menu Implementations (Replaced by DPG in Package)

| File | Status | Replacement |
|------|--------|-------------|
| `external_menu.py` | ✅ Archive | `cheat_menu.py` in package |
| `dpg_menu_subprocess.py` | ✅ Archive | `cheat_menu.py` in package |
| `imgui_menu.py` | ✅ Archive | `cheat_menu.py` in package |
| `minimal_menu.py` | ✅ Archive | `cheat_menu.py` in package |

### Legacy Launcher Scripts (In Package Now)

| File | Status | Replacement |
|------|--------|-------------|
| `launcher.py` | ✅ Archive | `phase4_apex_cheat_package/launcher.py` |
| `launch_phase4.py` | ✅ Archive | Same functionality in package |

### Main Entry Points (Package Has Better Structure)

| File | Status | Replacement |
|------|--------|-------------|
| `main.py` | ✅ Archive | `phase4_apex_cheat_package/launcher.py` |
| `launch_with_subprocess.py` | ✅ Archive | Same pattern in package |

### Test Files (Package Has Comprehensive Suite)

| File | Status | Replacement |
|------|--------|-------------|
| `test_minimal_dpg.py` | ✅ Archive | `tests/test_minimal.py` in package |
| `check_windows.py` | ✅ Archive | Legacy utility, can keep if needed |

### Documentation (Package Has Updated READMEs)

| File | Status | Notes |
|------|--------|-------|
| `README.md` | ✅ Archive | Keep as legacy reference |
| `LAUNCH_GUIDE.md` | ✅ Archive | Contains useful launch info |
| `DPG_FIX.md` | ✅ Archive | DPG compatibility notes |
| `DPG_CRASH_DIAGNOSIS.md` | ✅ Archive | DPG crash troubleshooting |

---

## Archive Process

### Step 1: Create Archive Directory
```bash
cd phase4_apex_cheat
mkdir archive
```

### Step 2: Move Obsolete Files
Move legacy files to `archive/` with descriptive names:
- `external_menu.py` → `archive/legacy_external_menu.py`
- `dpg_menu_subprocess.py` → `archive/legacy_dpg_subprocess.py`
- `imgui_menu.py` → `archive/legacy_imgui_menu.py`
- `minimal_menu.py` → `archive/legacy_minimal_menu.py`

### Step 3: Update Phase 4 README
Add note that package is the production version:
```
## Status: LEGACY (Consolidated into phase4_apex_cheat_package)

This directory contains legacy Phase 4 implementations.
The production version is now in `phase4_apex_cheat_package/`.
```

---

*Archive Plan - Created October 14, 2026*
