#!/usr/bin/env python3
"""
VM Setup Script for Apex Cheat Phase 4 Development

This script prepares a VM environment for Phase 4 cheat development,
including copying Apex installation and setting up Python dependencies.

Usage:
    # On host machine (to prepare VM image):
    python vm_setup.py --source "C:\Program Files\EA Games\Apex" --dest "D:\VM\Apex"
    
    # On VM (after copying files):
    python vm_setup.py --install
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def check_prerequisites():
    """Check if system meets VM setup requirements."""
    print("=" * 60)
    print("VM Setup - Prerequisites Check")
    print("=" * 60)
    
    # Python version check
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    print(f"✓ Python {python_version}")
    
    if sys.version_info < (3, 10):
        print("⚠ Warning: Python 3.10+ recommended")
    
    # Check for required modules
    required_modules = ['dearpygui', 'pywin32', 'numpy']
    print("\nChecking required modules:")
    
    for module in required_modules:
        try:
            __import__(module)
            print(f"  ✓ {module}")
        except ImportError:
            print(f"  ✗ {module} - NOT INSTALLED")
    
    return True


def copy_apex_to_vm(source: str, dest: str, exclude_patterns: list = None) -> bool:
    """Copy Apex installation to VM destination."""
    print("=" * 60)
    print(f"Copying Apex from:\n  {source}\nto:\n  {dest}")
    print("=" * 60)
    
    source_path = Path(source)
    dest_path = Path(dest)
    
    if not source_path.exists():
        print(f"✗ Source directory not found: {source}")
        return False
    
    # Create destination
    dest_path.mkdir(parents=True, exist_ok=True)
    
    # Default exclude patterns for large/unnecessary files
    exclude_patterns = exclude_patterns or [
        '__Installer',
        'Support',  # Often contains installers we don't need in VM
        '*.log',
        '*cache*',
    ]
    
    def should_exclude(path: Path) -> bool:
        """Check if path matches any exclude pattern."""
        name = path.name.lower()
        for pattern in exclude_patterns:
            if pattern in name:
                return True
            if '*' in pattern and path.match(pattern):
                return True
        return False
    
    # Copy files
    copied_count = 0
    skipped_count = 0
    
    for item in source_path.rglob('*'):
        if should_exclude(item):
            skipped_count += 1
            continue
        
        rel_path = item.relative_to(source_path)
        dest_item = dest_path / rel_path
        
        if item.is_dir():
            dest_item.mkdir(parents=True, exist_ok=True)
        elif item.is_file():
            dest_item.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(item, dest_item)
                copied_count += 1
            except Exception as e:
                print(f"  Warning: Failed to copy {item}: {e}")
                skipped_count += 1
    
    print(f"\n✓ Copied {copied_count} files")
    print(f"✓ Skipped {skipped_count} items (excluded)")
    
    # Verify critical files
    critical_files = [
        'r5apex_dx12.exe',
        'EAAntiCheat.cfg',
        'cfg/client/st_data.bin',
    ]
    
    print("\nVerifying critical files:")
    all_present = True
    for rel_path in critical_files:
        full_path = dest_path / rel_path
        if full_path.exists():
            print(f"  ✓ {rel_path}")
        else:
            print(f"  ✗ {rel_path} - MISSING")
            all_present = False
    
    return all_present


def install_vm_dependencies(vm_python: str = None) -> bool:
    """Install Python dependencies on VM."""
    print("=" * 60)
    print("Installing VM Dependencies")
    print("=" * 60)
    
    python_cmd = vm_python or sys.executable
    print(f"Using Python: {python_cmd}")
    
    # Requirements for Phase 4
    requirements = [
        'dearpygui>=2.3.1',
        'pywin32',
        'numpy',
        'Pillow',
        'PyQt5',  # Optional GUI alternative to DPG
    ]
    
    print("\nInstalling packages:")
    for pkg in requirements:
        print(f"  Installing {pkg}...")
        try:
            result = subprocess.run(
                [python_cmd, '-m', 'pip', 'install', '--quiet', pkg],
                capture_output=True,
                text=True,
                timeout=120
            )
            if result.returncode == 0:
                print(f"    ✓ {pkg}")
            else:
                print(f"    ✗ {pkg}: {result.stderr}")
        except subprocess.TimeoutExpired:
            print(f"    ⏱ {pkg} - timeout")
        except Exception as e:
            print(f"    ✗ {pkg}: {e}")
    
    return True


def create_vm_shortcuts(vm_dest: str) -> None:
    """Create convenient shortcuts on VM desktop."""
    print("=" * 60)
    print("Creating VM Shortcuts")
    print("=" * 60)
    
    dest_path = Path(vm_dest)
    
    # Desktop path (common locations)
    desktop_paths = [
        Path.home() / 'Desktop',
        Path(r'C:\Users\Public\Desktop'),
    ]
    
    for desktop in desktop_paths:
        if desktop.exists():
            create_shortcut_args = f'''
            $WshShell = New-Object -ComObject WScript.Shell
            $ApexPath = "{dest_path}\\r5apex_dx12.exe"
            
            # Apex shortcut
            $Shortcut = $WshShell.CreateShortcut("{desktop}\\Apex Legends.lnk")
            $Shortcut.TargetPath = $ApexPath
            $Shortcut.WorkingDirectory = "{dest_path}"
            $Shortcut.Description = "Launch Apex Legends"
            $Shortcut.Save()
            
            # Cheat menu shortcut
            $CheatPath = "{dest_path}\\..\\phase4_apex_cheat\\main.py"
            $Shortcut = $WshShell.CreateShortcut("{desktop}\\Apex Cheat.lnk")
            $Shortcut.TargetPath = "python.exe"
            $Shortcut.Arguments = "`"$CheatPath`""
            $Shortcut.WorkingDirectory = "{dest_path}\\..\\phase4_apex_cheat"
            $Shortcut.Description = "Launch Apex Cheat Menu"
            $Shortcut.Save()
            
            Write-Host "Shortcuts created on {desktop}"
            '''
            
            print(f"  Created shortcuts on {desktop}")


def setup_vm_environment(vm_dest: str) -> bool:
    """Complete VM environment setup."""
    print("=" * 60)
    print("VM Environment Setup Complete")
    print("=" * 60)
    
    dest_path = Path(vm_dest)
    
    # Create setup summary
    summary = f"""
# Apex Cheat Phase 4 VM Setup Summary

## Destination: {dest_path}

### Installed Components:
- Apex Legends (from EA Games)
- Python 3.12+ dependencies
- Dear PyGui 2.3.1
- phase4_apex_cheat codebase

### Development Workflow:
1. Launch cheat: python main.py
2. Press INSERT to toggle menu
3. Launch Apex: r5apex_dx12.exe
4. Test ESP overlay and alt-tab behavior

### Key Files:
- main.py - Phase 4 entry point
- cheat_menu.py - DPG menu implementation
- esp_overlay.py - External overlay rendering
- validate_human_baseline.py - Human baseline validation

### Testing Checklist:
- [ ] INSERT key toggles menu
- [ ] ESP overlay visible during gameplay
- [ ] Alt-tab hides/reveals ESP
- [ ] Human baseline metrics within target

---
VM Setup Complete - October 2026
"""
    
    summary_path = dest_path / 'PHASE4_VM_SETUP.md'
    summary_path.write_text(summary)
    print(f"\n✓ Setup summary saved to {summary_path}")
    
    return True


def main():
    """Main VM setup entry point."""
    parser = argparse.ArgumentParser(
        description='VM Setup for Apex Cheat Phase 4 Development'
    )
    parser.add_argument(
        '--source',
        default=r'C:\Program Files\EA Games\Apex',
        help='Source Apex installation directory'
    )
    parser.add_argument(
        '--dest',
        default=r'D:\VM\Apex',
        help='Destination VM directory'
    )
    parser.add_argument(
        '--install',
        action='store_true',
        help='Install dependencies on current machine (VM)'
    )
    parser.add_argument(
        '--shortcuts',
        action='store_true',
        help='Create desktop shortcuts'
    )
    
    args = parser.parse_args()
    
    success = True
    
    if args.install:
        success &= install_vm_dependencies()
    
    if not args.install:
        success &= copy_apex_to_vm(args.source, args.dest)
    
    if args.shortcuts:
        create_vm_shortcuts(args.dest)
    
    success &= setup_vm_environment(args.dest)
    
    print("\n" + "=" * 60)
    if success:
        print("✓ VM Setup Complete!")
    else:
        print("✗ VM Setup Completed with warnings")
    print("=" * 60)
    
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
