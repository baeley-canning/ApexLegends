/**
 * Python Wrapper for Apex Cheat - Chudvision/Ignite/Kernaim Style
 *
 * Provides easy configuration and control of the internal D3D11 overlay
 * from Python scripts
 */

import ctypes
from ctypes import c_bool, c_float, c_uint32, c_char_p, c_void_p
from typing import Optional, Dict, List, Tuple

# ============================================================================
// TYPE DEFINITIONS (matching C header)
// ============================================================================

class PlayerInfo(ctypes.Structure):
    _fields_ = [
        ("name", c_char_p),
        ("x", c_float),
        ("y", c_float),
        ("z", c_float),
        ("health", c_int),
        ("max_health", c_int),
        ("shield", c_int),
        ("max_shield", c_int),
        ("legend", c_char_p),
        ("weapon", c_char_p),
        ("is_enemy", c_bool),
        ("is_knocked", c_bool),
        ("distance", c_float),
    ]

class LegendSettings(ctypes.Structure):
    _fields_ = [
        ("legend_name", c_char_p),
        ("fov_degrees", c_float),
        ("smoothing", c_float),
        ("bone_priority", c_int),
        ("recoil_reduction", c_float),
        ("prediction_factor", c_float),
    ]

class TriggerbotConfig(ctypes.Structure):
    _fields_ = [
        ("enabled", c_bool),
        ("base_reaction_ms", c_int),
        ("min_reaction_ms", c_int),
        ("max_reaction_ms", c_int),
        ("weapon_delay_multiplier", c_float),
        ("micro_jitter_std", c_float),
        ("hold_fire_until_acquired", c_bool),
    ]

class CheatConfig(ctypes.Structure):
    _fields_ = [
        ("menu_enabled", c_bool),
        ("esp_enabled", c_bool),
        ("aimbot_enabled", c_bool),
        ("humanizer_enabled", c_bool),
        ("window_width", c_uint32),
        ("window_height", c_uint32),
        ("window_x", c_int32),
        ("window_y", c_int32),
        ("vsync", c_bool),
        ("transparent_background", c_bool),
        ("always_on_top", c_bool),
        ("menu_hotkey", c_uint32),
        ("esp_hotkey", c_uint32),
    ]

# ============================================================================
// CHEAT WRAPPER CLASS
// ============================================================================

class ApexCheat:
    def __init__(self, dll_path: str = "apex_cheat.dll"):
        self.dll = ctypes.WinDLL(dll_path)

        # Define function signatures
        self._define_functions()

    def _define_functions(self):
        """Define all C API function signatures"""
        
        # Initialization
        self.dll.CheatInitialize.argtypes = [c_void_p, ctypes.POINTER(CheatConfig)]
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

        # Aimbot operations
        self.dll.CheatEnableAimbot.argtypes = []
        self.dll.CheatEnableAimbot.restype = None
        
        self.dll.CheatDisableAimbot.argtypes = []
        self.dll.CheatDisableAimbot.restype = None
        
        self.dll.CheatToggleAimbot.argtypes = []
        self.dll.CheatToggleAimbot.restype = None
        
        self.dll.CheatIsAimbotEnabled.argtypes = []
        self.dll.CheatIsAimbotEnabled.restype = c_bool

        # Player management
        self.dll.CheatAddPlayer.argtypes = [ctypes.POINTER(PlayerInfo)]
        self.dll.CheatAddPlayer.restype = None
        
        self.dll.CheatRemovePlayer.argtypes = [c_char_p]
        self.dll.CheatRemovePlayer.restype = None
        
        self.dll.CheatGetPlayerCount.argtypes = []
        self.dll.CheatGetPlayerCount.restype = c_uint32
        
        self.dll.CheatGetPlayer.argtypes = [c_uint32]
        self.dll.CheatGetPlayer.restype = ctypes.POINTER(PlayerInfo)

        # Legend settings
        self.dll.CheatAddLegendSettings.argtypes = [ctypes.POINTER(LegendSettings)]
        self.dll.CheatAddLegendSettings.restype = None
        
        self.dll.CheatGetLegendSettings.argtypes = [c_char_p]
        self.dll.CheatGetLegendSettings.restype = ctypes.POINTER(LegendSettings)
        
        self.dll.CheatUpdateLegendSettings.argtypes = [c_char_p, ctypes.POINTER(LegendSettings)]
        self.dll.CheatUpdateLegendSettings.restype = None

        # Triggerbot configuration
        self.dll.CheatSetTriggerbotConfig.argtypes = [ctypes.POINTER(TriggerbotConfig)]
        self.dll.CheatSetTriggerbotConfig.restype = None
        
        self.dll.CheatGetTriggerbotConfig.argtypes = []
        self.dll.CheatGetTriggerbotConfig.restype = ctypes.POINTER(TriggerbotConfig)

        # Rendering
        self.dll.CheatRenderFrame.argtypes = [c_void_p]
        self.dll.CheatRenderFrame.restype = None
        
        self.dll.CheatPresentFrame.argtypes = [c_bool]
        self.dll.CheatPresentFrame.restype = None

        # Hotkey registration
        self.dll.CheatRegisterHotkeys.argtypes = []
        self.dll.CheatRegisterHotkeys.restype = c_bool
        
        self.dll.CheatUnregisterHotkeys.argtypes = []
        self.dll.CheatUnregisterHotkeys.restype = None

        # Triggerbot humanization
        self.dll.CheatGetReactionDelay.argtypes = []
        self.dll.CheatGetReactionDelay.restype = c_int
        
        self.dll.CheatGetMicroJitter.argtypes = []
        self.dll.CheatGetMicroJitter.restype = c_float

    def initialize(self, config: Optional[CheatConfig] = None) -> bool:
        """Initialize the cheat with optional configuration"""
        if config is None:
            config = CheatConfig()
            config.menu_enabled = True
            config.esp_enabled = True
            config.aimbot_enabled = True
            config.humanizer_enabled = True
            config.window_width = 600
            config.window_height = 450
            config.window_x = 100
            config.window_y = 100
            config.vsync = True
            config.transparent_background = True
            config.always_on_top = True
            config.menu_hotkey = 0x90  # INSERT
            config.esp_hotkey = 0x24   # HOME

        return self.dll.CheatInitialize(0, config)

    def shutdown(self):
        """Shutdown the cheat and release resources"""
        self.dll.CheatShutdown()

    def show_menu(self):
        """Show the cheat menu"""
        self.dll.CheatShowMenu()

    def hide_menu(self):
        """Hide the cheat menu"""
        self.dll.CheatHideMenu()

    def toggle_menu(self):
        """Toggle menu visibility"""
        self.dll.CheatToggleMenu()

    def is_menu_visible(self) -> bool:
        """Check if menu is visible"""
        return self.dll.CheatIsMenuVisible()

    def show_esp(self):
        """Show ESP overlay"""
        self.dll.CheatShowESP()

    def hide_esp(self):
        """Hide ESP overlay"""
        self.dll.CheatHideESP()

    def toggle_esp(self):
        """Toggle ESP visibility"""
        self.dll.CheatToggleESP()

    def is_esp_enabled(self) -> bool:
        """Check if ESP is enabled"""
        return self.dll.CheatIsESPEnabled()

    def enable_aimbot(self):
        """Enable aimbot"""
        self.dll.CheatEnableAimbot()

    def disable_aimbot(self):
        """Disable aimbot"""
        self.dll.CheatDisableAimbot()

    def toggle_aimbot(self):
        """Toggle aimbot"""
        self.dll.CheatToggleAimbot()

    def is_aimbot_enabled(self) -> bool:
        """Check if aimbot is enabled"""
        return self.dll.CheatIsAimbotEnabled()

    def add_player(self, name: str, x: float, y: float, z: float,
                   health: int, max_health: int, shield: int, max_shield: int,
                   legend: str, weapon: str, is_enemy: bool = True,
                   is_knocked: bool = False, distance: float = 50.0):
        """Add a player to the ESP list"""
        player = PlayerInfo()
        player.name = name.encode('utf-8')
        player.x = x
        player.y = y
        player.z = z
        player.health = health
        player.max_health = max_health
        player.shield = shield
        player.max_shield = max_shield
        player.legend = legend.encode('utf-8')
        player.weapon = weapon.encode('utf-8')
        player.is_enemy = is_enemy
        player.is_knocked = is_knocked
        player.distance = distance

        self.dll.CheatAddPlayer(ctypes.byref(player))

    def remove_player(self, name: str):
        """Remove a player from the ESP list"""
        self.dll.CheatRemovePlayer(name.encode('utf-8'))

    def get_player_count(self) -> int:
        """Get number of players in ESP list"""
        return int(self.dll.CheatGetPlayerCount())

    def get_player(self, index: int) -> Optional[PlayerInfo]:
        """Get player by index"""
        player_ptr = self.dll.CheatGetPlayer(index)
        if player_ptr:
            return player_ptr.contents
        return None

    def add_legend_settings(self, legend_name: str, fov_degrees: float,
                              smoothing: float, bone_priority: int = 0,
                              recoil_reduction: float = 0.6,
                              prediction_factor: float = 0.7):
        """Add or update legend-specific aimbot settings"""
        settings = LegendSettings()
        settings.legend_name = legend_name.encode('utf-8')
        settings.fov_degrees = fov_degrees
        settings.smoothing = smoothing
        settings.bone_priority = bone_priority
        settings.recoil_reduction = recoil_reduction
        settings.prediction_factor = prediction_factor

        self.dll.CheatAddLegendSettings(ctypes.byref(settings))

    def get_legend_settings(self, legend_name: str) -> Optional[LegendSettings]:
        """Get legend-specific aimbot settings"""
        settings_ptr = self.dll.CheatGetLegendSettings(legend_name.encode('utf-8'))
        if settings_ptr:
            return settings_ptr.contents
        return None

    def set_triggerbot_config(self, enabled: bool = True,
                                base_reaction_ms: int = 100,
                                min_reaction_ms: int = 50,
                                max_reaction_ms: int = 150,
                                weapon_delay_multiplier: float = 1.0,
                                micro_jitter_std: float = 1.5,
                                hold_fire_until_acquired: bool = True):
        """Configure triggerbot with humanization settings"""
        config = TriggerbotConfig()
        config.enabled = enabled
        config.base_reaction_ms = base_reaction_ms
        config.min_reaction_ms = min_reaction_ms
        config.max_reaction_ms = max_reaction_ms
        config.weapon_delay_multiplier = weapon_delay_multiplier
        config.micro_jitter_std = micro_jitter_std
        config.hold_fire_until_acquired = hold_fire_until_acquired

        self.dll.CheatSetTriggerbotConfig(ctypes.byref(config))

    def get_triggerbot_config(self) -> TriggerbotConfig:
        """Get current triggerbot configuration"""
        config_ptr = self.dll.CheatGetTriggerbotConfig()
        if config_ptr:
            return config_ptr.contents
        return TriggerbotConfig()

    def get_reaction_delay(self) -> int:
        """Get current reaction delay with humanization (50-150ms)"""
        return int(self.dll.CheatGetReactionDelay())

    def get_micro_jitter(self) -> float:
        """Get current micro-jitter value for human-like firing"""
        return float(self.dll.CheatGetMicroJitter())

    # ============================================================================
    // PHASE 4 ENHANCED FEATURES
    // ============================================================================

    def initialize_enhanced(self, config: Optional[CheatConfig] = None):
        """Initialize cheat with enhanced features (aimbot, triggerbot, weapon tracking)"""
        self.dll.Initialize(ctypes.byref(config) if config else None)

    def update(self):
        """Update cheat state each frame"""
        self.dll.Update()

    def shutdown_enhanced(self):
        """Shutdown enhanced cheat features"""
        self.dll.Shutdown()

    def toggle_aimbot(self):
        """Toggle aimbot on/off"""
        self.dll.ToggleAimbot()

    def toggle_triggerbot(self):
        """Toggle triggerbot on/off"""
        self.dll.ToggleTriggerbot()

    def toggle_weapon_tracking(self):
        """Toggle weapon tracking on/off"""
        self.dll.ToggleWeaponTracking()

    def get_status(self) -> str:
        """Get current cheat status as string"""
        return self.dll.GetStatus()

    def set_fov(self, fov: int):
        """Set aimbot field of view"""
        self.dll.SetFOV(fov)

    def set_trigger_delay(self, delay_ms: int):
        """Set triggerbot delay in milliseconds"""
        self.dll.SetTriggerDelay(delay_ms)

    def set_esp_distance(self, distance: int):
        """Set ESP distance limit in meters"""
        self.dll.SetESPDistance(distance)

    def render_frame(self, device_context: c_void_p):
        """Render a frame with menu, ESP, and aimbot"""
        self.dll.CheatRenderFrame(device_context)

    def present_frame(self, vsync: bool = True):
        """Present the rendered frame to screen"""
        self.dll.CheatPresentFrame(vsync)


# ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

def create_default_config() -> CheatConfig:
    """Create a default cheat configuration"""
    config = CheatConfig()
    config.menu_enabled = True
    config.esp_enabled = True
    config.aimbot_enabled = True
    config.humanizer_enabled = True
    config.window_width = 600
    config.window_height = 450
    config.window_x = 100
    config.window_y = 100
    config.vsync = True
    config.transparent_background = True
    config.always_on_top = True
    config.menu_hotkey = 0x90  # INSERT
    config.esp_hotkey = 0x24   # HOME
    return config


def create_wraith_settings() -> LegendSettings:
    """Create Wraith-specific aimbot settings (tight FOV)"""
    settings = LegendSettings()
    settings.legend_name = "Wraith".encode('utf-8')
    settings.fov_degrees = 6.0   # Tight FOV
    settings.smoothing = 0.85    # High smoothing
    settings.bone_priority = 0   # Head
    settings.recoil_reduction = 0.7
    settings.prediction_factor = 0.8
    return settings


def create_gibraltar_settings() -> LegendSettings:
    """Create Gibraltar-specific aimbot settings (loose FOV)"""
    settings = LegendSettings()
    settings.legend_name = "Gibraltar".encode('utf-8')
    settings.fov_degrees = 12.0  # Looser FOV
    settings.smoothing = 0.65    # Medium smoothing
    settings.bone_priority = 2   # Chest
    settings.recoil_reduction = 0.5
    settings.prediction_factor = 0.6
    return settings


def create_lifeline_settings() -> LegendSettings:
    """Create Lifeline-specific aimbot settings (balanced)"""
    settings = LegendSettings()
    settings.legend_name = "Lifeline".encode('utf-8')
    settings.fov_degrees = 9.0   # Balanced FOV
    settings.smoothing = 0.75    # Balanced smoothing
    settings.bone_priority = 1   # Neck
    settings.recoil_reduction = 0.6
    settings.prediction_factor = 0.7
    return settings


# ============================================================================
// END OF FILE
// ============================================================================
