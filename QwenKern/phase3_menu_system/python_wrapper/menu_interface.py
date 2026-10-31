"""
Python wrapper for Phase 3 menu system (C++/ImGui core)
Provides configuration management and hotkey registration
"""

import ctypes
from ctypes import wintypes
import threading
import time
from dataclasses import dataclass, field
from typing import Dict, Any, Optional
import json
import os

# Shared memory structure matching C++ implementation
@dataclass
class SharedMenuData:
    """Matches SharedMenuData in menu_config.hpp"""
    MenuVisible: bool = False
    MenuActive: bool = True
    AimbotEnabled: bool = False
    ESPEnabled: bool = True
    GlowEnabled: bool = True
    SkeletonEnabled: bool = True
    FOV: float = 22.0
    MaxDynamicFOV: float = 200.0
    SmoothingX: float = 15.0
    SmoothingY: float = 16.0
    DeadZone: float = 5.0
    MaxDistance: float = 250.0
    UseLeftMouse: bool = True
    UseLeftControl: bool = False
    VisibilityCheck: bool = True
    PredictionEnabled: bool = True
    LowLatencyMode: bool = False
    FPSTarget: int = 144
    Streamproof: bool = True
    WatermarkControl: bool = True
    
    # Legend-specific overrides (Wraith tight, Gibraltar loose)
    LegendConfigs: Dict[str, Dict[str, float]] = field(default_factory=lambda: {
        'Wraith': {'FOVMultiplier': 1.2, 'SmoothingMultiplier': 0.8, 'ReactionTime': 75.0},
        'Gibraltar': {'FOVMultiplier': 0.9, 'SmoothingMultiplier': 1.2, 'ReactionTime': 125.0},
        'Bangalore': {'FOVMultiplier': 1.0, 'SmoothingMultiplier': 1.0, 'ReactionTime': 100.0},
        'Caustic': {'FOVMultiplier': 0.95, 'SmoothingMultiplier': 1.1, 'ReactionTime': 110.0},
        'Mirage': {'FOVMultiplier': 1.1, 'SmoothingMultiplier': 0.9, 'ReactionTime': 90.0},
        'Octane': {'FOVMultiplier': 1.15, 'SmoothingMultiplier': 0.85, 'ReactionTime': 85.0},
        'Pathfinder': {'FOVMultiplier': 1.05, 'SmoothingMultiplier': 1.0, 'ReactionTime': 95.0},
        'Rampart': {'FOVMultiplier': 0.95, 'SmoothingMultiplier': 1.1, 'ReactionTime': 110.0},
        'Horizon': {'FOVMultiplier': 1.0, 'SmoothingMultiplier': 1.0, 'ReactionTime': 100.0},
        'Flores': {'FOVMultiplier': 1.0, 'SmoothingMultiplier': 1.0, 'ReactionTime': 100.0},
        'Lifeline': {'FOVMultiplier': 1.0, 'SmoothingMultiplier': 1.0, 'ReactionTime': 100.0},
        'Doppler': {'FOVMultiplier': 1.0, 'SmoothingMultiplier': 1.0, 'ReactionTime': 100.0},
    })


class MenuInterface:
    """Python interface to C++/ImGui menu system"""
    
    def __init__(self, dll_path: Optional[str] = None):
        self.dll_path = dll_path or "phase3_menu_system/imgui_integration/ApexCheatMenu.dll"
        self._dll = None
        self._shared_data = SharedMenuData()
        self._hotkey_thread: Optional[threading.Thread] = None
        self._running = False
        
    def load_dll(self) -> bool:
        """Load the C++ menu DLL"""
        try:
            self._dll = ctypes.WinDLL(self.dll_path)
            
            # Set up function signatures
            self._dll.Menu_IsVisible.argtypes = []
            self._dll.Menu_IsVisible.restype = wintypes.BOOL
            
            self._dll.Menu_SetVisible.argtypes = [wintypes.BOOL]
            self._dll.Menu_SetVisible.restype = None
            
            self._dll.Menu_UpdateData.argtypes = [ctypes.POINTER(SharedMenuData)]
            self._dll.Menu_UpdateData.restype = None
            
            self._dll.Menu_GetData.argtypes = []
            self._dll.Menu_GetData.restype = ctypes.POINTER(SharedMenuData)
            
            return True
        except Exception as e:
            print(f"Failed to load menu DLL: {e}")
            return False
    
    def start(self) -> bool:
        """Start the menu system"""
        if not self._dll:
            if not self.load_dll():
                return False
        
        self._running = True
        
        # Register hotkeys
        self._register_hotkeys()
        
        # Start hotkey monitoring thread
        self._hotkey_thread = threading.Thread(target=self._hotkey_loop, daemon=True)
        self._hotkey_thread.start()
        
        print("Menu system started")
        return True
    
    def stop(self) -> None:
        """Stop the menu system"""
        self._running = False
        if self._hotkey_thread:
            self._hotkey_thread.join(timeout=2.0)
        print("Menu system stopped")
    
    def toggle_menu(self) -> None:
        """Toggle menu visibility"""
        current = self.is_visible()
        self.set_visible(not current)
    
    def is_visible(self) -> bool:
        """Check if menu is visible"""
        if not self._dll:
            return self._shared_data.MenuVisible
        return self._dll.Menu_IsVisible()
    
    def set_visible(self, visible: bool) -> None:
        """Set menu visibility"""
        if self._dll:
            self._dll.Menu_SetVisible(visible)
        self._shared_data.MenuVisible = visible
    
    def update_menu_data(self, data: SharedMenuData) -> None:
        """Update shared menu data with C++ core"""
        if self._dll:
            self._dll.Menu_UpdateData(ctypes.byref(data))
        self._shared_data = data
    
    def get_menu_data(self) -> SharedMenuData:
        """Get current menu data from C++ core"""
        if self._dll:
            ptr = self._dll.Menu_GetData()
            if ptr:
                return ptr.contents
        return self._shared_data
    
    def save_config(self, config_path: Optional[str] = None) -> None:
        """Save configuration to JSON file"""
        path = config_path or "menu_config.json"
        config = {
            'MenuVisible': self._shared_data.MenuVisible,
            'MenuActive': self._shared_data.MenuActive,
            'AimbotEnabled': self._shared_data.AimbotEnabled,
            'ESPEnabled': self._shared_data.ESPEnabled,
            'GlowEnabled': self._shared_data.GlowEnabled,
            'SkeletonEnabled': self._shared_data.SkeletonEnabled,
            'FOV': self._shared_data.FOV,
            'MaxDynamicFOV': self._shared_data.MaxDynamicFOV,
            'SmoothingX': self._shared_data.SmoothingX,
            'SmoothingY': self._shared_data.SmoothingY,
            'DeadZone': self._shared_data.DeadZone,
            'MaxDistance': self._shared_data.MaxDistance,
            'UseLeftMouse': self._shared_data.UseLeftMouse,
            'UseLeftControl': self._shared_data.UseLeftControl,
            'VisibilityCheck': self._shared_data.VisibilityCheck,
            'PredictionEnabled': self._shared_data.PredictionEnabled,
            'LegendConfigs': self._shared_data.LegendConfigs,
        }
        
        with open(path, 'w') as f:
            json.dump(config, f, indent=2)
        print(f"Configuration saved to {path}")
    
    def load_config(self, config_path: Optional[str] = None) -> bool:
        """Load configuration from JSON file"""
        path = config_path or "menu_config.json"
        
        if not os.path.exists(path):
            print(f"Config file not found: {path}")
            return False
        
        try:
            with open(path, 'r') as f:
                config = json.load(f)
            
            self._shared_data.MenuVisible = config.get('MenuVisible', False)
            self._shared_data.MenuActive = config.get('MenuActive', True)
            self._shared_data.AimbotEnabled = config.get('AimbotEnabled', False)
            self._shared_data.ESPEnabled = config.get('ESPEnabled', True)
            self._shared_data.GlowEnabled = config.get('GlowEnabled', True)
            self._shared_data.SkeletonEnabled = config.get('SkeletonEnabled', True)
            self._shared_data.FOV = config.get('FOV', 22.0)
            self._shared_data.MaxDynamicFOV = config.get('MaxDynamicFOV', 200.0)
            self._shared_data.SmoothingX = config.get('SmoothingX', 15.0)
            self._shared_data.SmoothingY = config.get('SmoothingY', 16.0)
            self._shared_data.DeadZone = config.get('DeadZone', 5.0)
            self._shared_data.MaxDistance = config.get('MaxDistance', 250.0)
            self._shared_data.UseLeftMouse = config.get('UseLeftMouse', True)
            self._shared_data.UseLeftControl = config.get('UseLeftControl', False)
            self._shared_data.VisibilityCheck = config.get('VisibilityCheck', True)
            self._shared_data.PredictionEnabled = config.get('PredictionEnabled', True)
            self._shared_data.LegendConfigs = config.get('LegendConfigs', {})
            
            # Update C++ core if available
            if self._dll:
                self._dll.Menu_UpdateData(ctypes.byref(self._shared_data))
            
            print(f"Configuration loaded from {path}")
            return True
        except Exception as e:
            print(f"Failed to load config: {e}")
            return False
    
    def _register_hotkeys(self) -> None:
        """Register global hotkeys"""
        user32 = ctypes.windll.user32
        
        # INSERT key - Toggle menu
        user32.RegisterHotKey(None, 1, 0, 0x2D)  # VK_INSERT
        
        # HOME key - Toggle ESP
        user32.RegisterHotKey(None, 2, 0, 0x24)  # VK_HOME
    
    def _hotkey_loop(self) -> None:
        """Monitor hotkey events"""
        user32 = ctypes.windll.user32
        
        msg = ctypes.wintypes.MSG()
        while self._running:
            if user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, 1):
                if msg.message == 0x0312:  # WM_HOTKEY
                    if msg.wParam == 1:  # INSERT
                        self.toggle_menu()
                    elif msg.wParam == 2:  # HOME
                        self._shared_data.ESPEnabled = not self._shared_data.ESPEnabled
                        if self._dll:
                            self._dll.Menu_UpdateData(ctypes.byref(self._shared_data))
                user32.TranslateMessage(ctypes.byref(msg))
                user32.DispatchMessageW(ctypes.byref(msg))
            
            time.sleep(0.01)  # 10ms polling


def main():
    """Demo: Start menu system and show basic functionality"""
    menu = MenuInterface()
    
    if not menu.start():
        print("Failed to start menu system")
        return
    
    print("\n=== Apex Legends Menu System ===")
    print(f"Menu visible: {menu.is_visible()}")
    print(f"Aimbot enabled: {menu._shared_data.AimbotEnabled}")
    print(f"ESP enabled: {menu._shared_data.ESPEnabled}")
    print(f"\nHotkeys registered:")
    print("  INSERT - Toggle Menu")
    print("  HOME - Toggle ESP")
    
    # Demo: Update some settings
    menu._shared_data.FOV = 25.0
    menu._shared_data.SmoothingX = 18.0
    menu.update_menu_data(menu._shared_data)
    
    print(f"\nUpdated settings:")
    print(f"  FOV: {menu._shared_data.FOV}")
    print(f"  Smoothing X: {menu._shared_data.SmoothingX}")
    
    # Demo: Save configuration
    menu.save_config()
    
    print("\nMenu system running. Press INSERT to toggle menu visibility.")
    print("Press Ctrl+C to exit...")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        menu.stop()


if __name__ == "__main__":
    main()
