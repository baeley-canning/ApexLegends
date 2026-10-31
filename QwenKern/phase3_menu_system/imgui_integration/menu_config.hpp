#pragma once

#include <Windows.h>

// ---------------------------------------------------------------------------
// Menu configuration matching Kernaim / Ignite / Chudvision patterns
// ---------------------------------------------------------------------------
struct MenuConfig {
    // Window positioning
    bool  AutoPosition       = true;
    int   WindowX            = 60;
    int   WindowY            = 60;
    int   WindowWidth        = 620;
    int   WindowHeight       = 520;

    // Theme
    bool  DarkTheme          = true;
    bool  TransparentOverlay = true;
    float TransparencyAlpha  = 0.95f;

    // Hotkeys (virtual-key codes)
    int   ToggleKey          = 0x2D; // INSERT
    int   HomeKey            = 0x24; // HOME

    // Tabs
    const char* TabNames[4] = { "Aimbot", "Visuals", "Misc", "Colors" };
};

// ---------------------------------------------------------------------------
// SharedMenuData
//
// Single source of truth for the whole menu.  This exact layout is what gets
// published into the named section Global\ApexCheatMenuData so a kernel driver
// or a python wrapper can read the user's configuration.
//
// NOTE: this used to be declared twice (here, and again in shared_memory.hpp
// with a *different* set of members).  That mismatch is why menu_core.cpp
// referenced members that did not exist and could never compile.  It is now
// declared exactly once.
// ---------------------------------------------------------------------------
struct SharedMenuData {
    // Menu state
    bool  MenuVisible        = true;
    bool  MenuActive         = true;

    // Feature flags
    bool  AimbotEnabled      = false;
    bool  ESPEnabled         = true;
    bool  GlowEnabled        = true;
    bool  SkeletonEnabled    = true;

    // Aimbot settings
    float FOV                = 22.0f;
    float MaxDynamicFOV      = 200.0f;
    float SmoothingX         = 15.0f;
    float SmoothingY         = 16.0f;
    float DeadZone           = 5.0f;
    float MaxDistance        = 250.0f;
    int   AimBone            = 0;     // 0=Head 1=Neck 2=Chest 3=UpperChest

    // Input
    bool  UseLeftMouse       = true;
    bool  UseLeftControl     = false;
    bool  VisibilityCheck    = true;
    bool  PredictionEnabled  = true;

    // Performance / anti-detection
    bool  LowLatencyMode     = false;
    int   FPSTarget          = 144;
    bool  Streamproof        = false;
    bool  WatermarkControl   = false;

    // Legend-specific overrides (Wraith tight, Gibraltar loose)
    struct LegendConfig {
        float FOVMultiplier       = 1.0f;
        float SmoothingMultiplier = 1.0f;
        float ReactionTime        = 100.0f; // 50-150ms humanized range
    } LegendConfigs[12];

    // Runtime counters
    int   FramesRendered     = 0;
    int   FramesSkipped      = 0;
    float AverageFPS         = 0.0f;
};
