#pragma once

#include <Windows.h>
#include <vector>
#include <string>

#include "menu_config.hpp"

// ---------------------------------------------------------------------------
// ESP rendering configuration (drives the Visuals / Colors tabs)
// ---------------------------------------------------------------------------
struct ESPConfig {
    bool Enabled = true;

    enum BoxStyle { Outline = 0, Filled = 1, Corner = 2 };
    BoxStyle Style = Outline;

    struct Colors {
        COLORREF TeamColor   = RGB(0, 120, 215);
        COLORREF EnemyColor  = RGB(220, 50, 50);
        COLORREF DownedColor = RGB(255, 165, 0);
        COLORREF GlowColor   = RGB(255, 255, 255);
    } Colors;

    bool ShowBoxes      = true;
    bool ShowGlow       = true;
    bool ShowSkeletons  = true;
    bool ShowHealthBars = true;
    bool ShowDistance   = true;
    bool ShowSnaplines  = false;

    float BoxThickness  = 1.5f;
    float GlowIntensity = 2.0f;
};
