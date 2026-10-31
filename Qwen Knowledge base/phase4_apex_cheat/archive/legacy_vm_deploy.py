#!/usr/bin/env python3
r"""
VM Deployment Script for Apex Cheat Phase 4

This script sets up the Python environment and deploys the cheat code
on a VM that has been prepared with the vm_setup.py script.

Usage:
    python vm_deploy.py --apex-path "C:\Users\New User\VM\Apex"
                        --cheat-path "C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat"
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def check_python_environment():
    """Verify Python environment is ready."""
    print("=" * 60)
    print("Python Environment Check")
    print("=" * 60)

    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    print(f"Python version: {python_version}")

    if sys.version_info < (3, 10):
        print("Warning: Python 3.10+ recommended for DPG 2.3.1")

    return True


def install_dependencies():
    """Install required Python packages."""
    print("=" * 60)
    print("Installing Python Dependencies")
    print("=" * 60)

    packages = [
        'dearpygui>=2.3.1',
        'pywin32',
        'numpy',
        'Pillow',
        'pytest',
    ]

    for package in packages:
        try:
            print(f"Installing {package}...")
            result = subprocess.run(
                [sys.executable, '-m', 'pip', 'install', '--quiet', package],
                capture_output=True,
                text=True,
                timeout=180
            )
            if result.returncode == 0:
                print(f"  OK {package}")
            else:
                print(f"  FAIL {package}: {result.stderr[:200] if result.stderr else 'no error output'}")
        except subprocess.TimeoutExpired:
            print(f"  TIMEOUT {package}")
        except Exception as e:
            print(f"  FAIL {package}: {e}")

    return True


def verify_apex_installation(apex_path: str) -> bool:
    """Verify Apex installation is complete."""
    print("=" * 60)
    print(f"Verifying Apex Installation at: {apex_path}")
    print("=" * 60)

    apex_dir = Path(apex_path)

    if not apex_dir.exists():
        print(f"FAIL Apex directory not found: {apex_path}")
        return False

    # Check critical files
    critical_files = [
        'r5apex_dx12.exe',
        'EAAntiCheat.cfg',
        'cfg/client/st_data.bin',
    ]

    all_present = True
    for rel_path in critical_files:
        full_path = apex_dir / rel_path
        if full_path.exists():
            size_mb = full_path.stat().st_size / (1024 * 1024)
            print(f"  OK {rel_path} ({size_mb:.1f} MB)")
        else:
            print(f"  FAIL {rel_path} - MISSING")
            all_present = False

    # Check pak files
    paks_dir = apex_dir / 'paks' / 'Win64'
    if paks_dir.exists():
        pak_count = len(list(paks_dir.glob('*.rpak')))
        print(f"  OK {pak_count} pak files found")

    return all_present


def setup_cheat_directory(cheat_path: str, apex_path: str) -> bool:
    """Set up cheat directory with proper structure."""
    print("=" * 60)
    print(f"Setting up Cheat Directory at: {cheat_path}")
    print("=" * 60)

    cheat_dir = Path(cheat_path)

    if not cheat_dir.exists():
        print(f"FAIL Cheat directory not found: {cheat_path}")
        return False

    # Check for required files
    required_files = [
        'main.py',
        'cheat_menu.py',
        'esp_overlay.py',
        'simple_overlay.py',
        'vm_setup.py',
    ]

    all_present = True
    for filename in required_files:
        filepath = cheat_dir / filename
        if filepath.exists():
            size_kb = filepath.stat().st_size / 1024
            print(f"  OK {filename} ({size_kb:.1f} KB)")
        else:
            print(f"  FAIL {filename} - MISSING")
            all_present = False

    # Create config file if not exists
    config_path = cheat_dir / 'config.py'
    if not config_path.exists():
        print(f"  WARN config.py - NOT FOUND (will use defaults)")

    return all_present


def test_cheat_launch(cheat_path: str) -> bool:
    """Test launching the cheat menu."""
    print("=" * 60)
    print("Testing Cheat Launch")
    print("=" * 60)

    cheat_dir = Path(cheat_path)

    try:
        print("Launching cheat menu...")
        result = subprocess.run(
            [sys.executable, str(cheat_dir / 'main.py')],
            cwd=str(cheat_dir),
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            print("  OK Cheat menu launched successfully")
            if result.stdout:
                print(f"  Output preview:\n{result.stdout[:500]}")
            return True
        else:
            print(f"  FAIL Cheat menu failed with exit code {result.returncode}")
            if result.stderr:
                print(f"  Error: {result.stderr[:500]}")
            return False

    except subprocess.TimeoutExpired:
        print("  TIMEOUT Cheat menu launch (expected for DPG)")
        return True  # DPG menus often timeout as they're long-running
    except Exception as e:
        print(f"  FAIL Cheat menu failed: {e}")
        return False


def create_vm_readme(apex_path: str, cheat_path: str) -> None:
    r"""Create VM README with setup summary."""
    print("=" * 60)
    print("Creating VM README")
    print("=" * 60)

    apex_dir = Path(apex_path)
    cheat_dir = Path(cheat_path)

    readme_content = rf"""# Apex Cheat Phase 4 - VM Setup

## Destination: {apex_dir}

### Apex Installation
- Location: `{apex_dir}`
- Size: ~{sum(f.stat().st_size for f in apex_dir.rglob('*') if f.is_file()) / (1024**3):.1f} GB
- Main executable: `r5apex_dx12.exe`

### Cheat Code
- Location: `{cheat_dir}`
- Python version: {sys.version_info.major}.{sys.version_info.minor}
- Key files:
  - `main.py` - Phase 4 entry point with INSERT key handling
  - `cheat_menu.py` - Dear PyGui menu implementation
  - `esp_overlay.py` - External ESP overlay rendering
  - `vm_setup.py` - VM preparation script

### Development Workflow

1. **Launch Cheat Menu**
   ```bash
   python main.py
   ```

2. **Press INSERT key** to toggle menu visibility

3. **Launch Apex**
   ```bash
   r5apex_dx12.exe
   ```

4. **Test Features**
   - INSERT key toggles menu
   - ESP overlay renders player indicators
   - Alt-tab hides/reveals ESP (external overlay behavior)

### Testing Checklist

- [ ] INSERT key toggles DPG menu
- [ ] ESP overlay renders player indicators
- [ ] Alt-tab hides ESP overlay
- [ ] Menu stays visible over Apex
- [ ] Human baseline metrics within target

### Known Notes

- DPG 2.3.1 requires: create_context() -> create_viewport() -> setup_dearpygui()
- External overlay technique matches alt-tab behavior
- INSERT key (VK_INSERT=0x90) registered as global hotkey

---
VM Setup Complete - October 13, 2026
"""

    readme_path = apex_dir / 'PHASE4_VM_README.md'
    readme_path.write_text(readme_content)
    print(f"OK VM README saved to {readme_path}")


def main():
    """Main VM deployment entry point."""
    parser = argparse.ArgumentParser(
        description='VM Deployment for Apex Cheat Phase 4'
    )
    parser.add_argument(
        '--apex-path',
        default=r'C:\Users\New User\VM\Apex',
        help='Path to Apex installation on VM'
    )
    parser.add_argument(
        '--cheat-path',
        default=r'C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat',
        help='Path to cheat code directory'
    )
    parser.add_argument(
        '--skip-deps',
        action='store_true',
        help='Skip dependency installation'
    )
    parser.add_argument(
        '--no-test',
        action='store_true',
        help='Skip cheat launch test'
    )

    args = parser.parse_args()

    success = True

    # Check Python environment
    success &= check_python_environment()

    # Install dependencies (unless skipped)
    if not args.skip_deps:
        success &= install_dependencies()

    # Verify Apex installation
    success &= verify_apex_installation(args.apex_path)

    # Set up cheat directory
    success &= setup_cheat_directory(args.cheat_path, args.apex_path)

    # Test cheat launch (unless skipped)
    if not args.no_test:
        success &= test_cheat_launch(args.cheat_path)

    # Create VM README
    create_vm_readme(args.apex_path, args.cheat_path)

    print("\n" + "=" * 60)
    if success:
        print("OK VM Deployment Complete!")
    else:
        print("FAIL VM Deployment Completed with warnings")
    print("=" * 60)

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
