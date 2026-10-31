/**
 * Python Wrapper for Apex Cheat Phase 5 C++ DLL
 * 
 * Provides easy configuration and scripting interface
 * Follows Chudvision hybrid pattern (Python + C++ DLL)
 */

import ctypes
from ctypes import c_bool, c_uint32, c_float, c_char_p, c_wchar_p
from dataclasses import dataclass
from typing import Optional, List, Tuple


# ============================================================================
# C STRUCT DEFINITIONS (matching apex_cheat.h)
# ============================================================================

@dataclass
class CheatConfig:
    """Configuration for Apex Cheat."""
    menu_enabled: bool = True
    esp_enabled: bool = True
    aimbot_enabled: bool = True
    humanizer_enabled: bool = True
    window_width: int = 600
    window_height: int = 450
    window_x: int = 100
    window_y: int = 100
    vsync: bool = True
    transparent_background: bool = True
    always_on_top: bool = True
    menu_hotkey: int = 0x90  # INSERT
    esp_hotkey: int = 0x24   # HOME


@dataclass
class PlayerInfo:
    """Player information for ESP."""
    name: str
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    health: int = 100
    max_health: int = 100
    shield: int = 0
    max_shield: int = 100
    legend: str = "Lifeline"
    weapon: str = "R-99"
    is_enemy: bool = True
    is_knocked: bool = False


# ============================================================================
# C API FUNCTION PROTOTYPES
# ============================================================================

class ApexCheatDLL:
    """Python wrapper for Apex Cheat C++ DLL."""
    
    def __init__(self, dll_path: str = "apex_cheat.dll"):
        self.dll_path = dll_path
        self.dll = ctypes.WinDLL(dll_path)
        
        # Define function signatures
        self._define_functions()
        
        # Initialize with default config
        self.config = CheatConfig()

    def _define_functions(self) -> None:
        """Define C API function signatures."""
        # Initialization
        self.dll.CheatInitialize.argtypes = [ctypes.c_void_p, ctypes.POINTER(CheatConfig)]
        self.dll.CheatInitialize.restype = c_bool
        
        self.dll.CheatShutdown.argtypes = []
        self.dll.CheatShutdown.restype = None
        
        # Menu operations
        self.dll.CheatShowMenu.argtypes = []
        self.dll.CheatShowMenu.restype = None
        
        self.dll.CheatHideMenu.argtypes = []
        self.dll.CheatHideMenu.restype = None
        
        self.dll.CheatToggleMenu.argtypes = []
        self.dll.CheatToggleMenu.restype = None
        
        self.dll.CheatIsMenuVisible.argtypes = []
        self.dll.CheatIsMenuVisible.restype = c_bool
        
        # ESP operations
        self.dll.CheatShowESP.argtypes = []
        self.dll.CheatShowESP.restype = None
        
        self.dll.CheatHideESP.argtypes = []
        self.dll.CheatHideESP.restype = None
        
        self.dll.CheatToggleESP.argtypes = []
        self.dll.CheatToggleESP.restype = None
        
        self.dll.CheatIsESPEnabled.argtypes = []
        self.dll.CheatIsESPEnabled.restype = c_bool
        
        # Player management
        self.dll.CheatAddPlayer.argtypes = [ctypes.POINTER(PlayerInfo)]
        self.dll.CheatAddPlayer.restype = None
        
        self.dll.CheatRemovePlayer.argtypes = [c_char_p]
        self.dll.CheatRemovePlayer.restype = None
        
        self.dll.CheatGetPlayerCount.argtypes = []
        self.dll.CheatGetPlayerCount.restype = ctypes.c_size_t
        
        self.dll.CheatGetPlayer.argtypes = [ctypes.c_size_t]
        self.dll.CheatGetPlayer.restype = ctypes.POINTER(PlayerInfo)
        
        # Rendering
        self.dll.CheatRenderFrame.argtypes = [ctypes.c_void_p]
        self.dll.CheatRenderFrame.restype = None
        
        # Hotkey registration
        self.dll.CheatRegisterHotkeys.argtypes = []
        self.dll.CheatRegisterHotkeys.restype = c_bool
        
        self.dll.CheatUnregisterHotkeys.argtypes = []
        self.dll.CheatUnregisterHotkeys.restype = None

    def initialize(self, config: Optional[CheatConfig] = None) -> bool:
        """Initialize the cheat DLL."""
        if config is None:
            config = self.config
        
        return self.dll.CheatInitialize(None, ctypes.byref(config))

    def shutdown(self) -> None:
        """Shutdown the cheat DLL."""
        self.dll.CheatShutdown()

    def show_menu(self) -> None:
        """Show the cheat menu."""
        self.dll.CheatShowMenu()

    def hide_menu(self) -> None:
        """Hide the cheat menu."""
        self.dll.CheatHideMenu()

    def toggle_menu(self) -> None:
        """Toggle menu visibility."""
        self.dll.CheatToggleMenu()

    def is_menu_visible(self) -> bool:
        """Check if menu is visible."""
        return self.dll.CheatIsMenuVisible()

    def show_esp(self) -> None:
        """Show ESP overlay."""
        self.dll.CheatShowESP()

    def hide_esp(self) -> None:
        """Hide ESP overlay."""
        self.dll.CheatHideESP()

    def toggle_esp(self) -> None:
        """Toggle ESP visibility."""
        self.dll.CheatToggleESP()

    def is_esp_enabled(self) -> bool:
        """Check if ESP is enabled."""
        return self.dll.CheatIsESPEnabled()

    def add_player(self, player: PlayerInfo) -> None:
        """Add a player for ESP rendering."""
        self.dll.CheatAddPlayer(ctypes.byref(player))

    def remove_player(self, name: str) -> None:
        """Remove a player by name."""
        self.dll.CheatRemovePlayer(name.encode('utf-8'))

    def get_player_count(self) -> int:
        """Get number of tracked players."""
        return int(self.dll.CheatGetPlayerCount())

    def get_player(self, index: int) -> Optional[PlayerInfo]:
        """Get player by index."""
        player_ptr = self.dll.CheatGetPlayer(index)
        if player_ptr:
            return player_ptr.contents
        return None

    def render_frame(self) -> None:
        """Render a frame (menu + ESP)."""
        self.dll.CheatRenderFrame(None)

    def register_hotkeys(self) -> bool:
        """Register global hotkeys (INSERT/HOME)."""
        return self.dll.CheatRegisterHotkeys()

    def unregister_hotkeys(self) -> None:
        """Unregister global hotkeys."""
        self.dll.CheatUnregisterHotkeys()


# ============================================================================
# CONVENIENCE WRAPPER CLASS
# ============================================================================

class ApexCheat:
    """High-level Python wrapper for Apex Cheat."""
    
    def __init__(self, dll_path: str = "apex_cheat.dll"):
        self.dll_wrapper = ApexCheatDLL(dll_path)
        self.running = False

    def start(self) -> None:
        """Start the cheat system."""
        print("Initializing Apex Cheat...")
        
        if self.dll_wrapper.initialize():
            self.dll_wrapper.register_hotkeys()
            self.running = True
            print("Apex Cheat started successfully")
        else:
            raise RuntimeError("Failed to initialize Apex Cheat")

    def stop(self) -> None:
        """Stop the cheat system."""
        if self.running:
            self.dll_wrapper.unregister_hotkeys()
            self.dll_wrapper.shutdown()
            self.running = False
            print("Apex Cheat stopped")

    def toggle_menu(self) -> None:
        """Toggle menu visibility via hotkey."""
        self.dll_wrapper.toggle_menu()

    def toggle_esp(self) -> None:
        """Toggle ESP visibility via hotkey."""
        self.dll_wrapper.toggle_esp()

    def add_test_players(self, count: int = 5) -> None:
        """Add test players for ESP demo."""
        legends = ["Lifeline", "Wraith", "Gibraltar", "Newcastle", "Bangalore"]
        weapons = ["R-99", "R-301", "Wingman", "Sentinel", "Peacekeeper"]
        
        for i in range(count):
            player = PlayerInfo(
                name=f"Player{i+1}",
                x=100.0 + i * 80.0,
                y=200.0,
                z=0.0,
                health=100 - i * 10,
                max_health=100,
                shield=50,
                max_shield=100,
                legend=legends[i % len(legends)],
                weapon=weapons[i % len(weapons)],
                is_enemy=True,
                is_knocked=False
            )
            self.dll_wrapper.add_player(player)
        
        print(f"Added {count} test players")


# ============================================================================
# DEMO USAGE
# ============================================================================

def main():
    """Demo usage of Apex Cheat Python wrapper."""
    cheat = ApexCheat("apex_cheat.dll")
    
    try:
        cheat.start()
        
        # Add test players
        cheat.add_test_players(count=5)
        
        # Display current state
        print(f"Menu visible: {cheat.dll_wrapper.is_menu_visible()}")
        print(f"ESP enabled: {cheat.dll_wrapper.is_esp_enabled()}")
        print(f"Player count: {cheat.dll_wrapper.get_player_count()}")
        
        # Main loop
        print("\nApex Cheat running - Press INSERT to toggle menu, HOME to toggle ESP")
        input("Press Enter to stop...")
        
    finally:
        cheat.stop()


if __name__ == "__main__":
    main()
