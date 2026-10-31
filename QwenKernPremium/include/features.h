#pragma once
#include <windows.h>

// Forward declarations
class MemoryReader;

enum FeatureType {
    FEATURE_AIMBOT = 0,
    FEATURE_ESP = 1,
    FEATURE_GLOW = 2,
    FEATURE_RECOIL = 3
};

class CheatFeatures {
private:
    bool featuresEnabled[4]; // Array for the four feature types
    
public:
    CheatFeatures();
    ~CheatFeatures() = default;
    
    void EnableFeature(FeatureType type, bool enable);
    bool IsFeatureEnabled(FeatureType type) const;
    
    // Individual feature functions
    void UpdateAimbot(MemoryReader* reader);
    void UpdateESP(MemoryReader* reader);
    void UpdateGlow(MemoryReader* reader);
    void UpdateRecoilCompensation(MemoryReader* reader);
    
private:
    // Feature-specific variables
    float aimbotSmoothness;
    bool bDrawLines;
    bool bDrawBoxes;
    bool bDrawNames;
};

// Global feature instance
extern CheatFeatures* g_pCheatFeatures;

// ============================================================================
// ESP data contract
//
// features.cpp fills this buffer (memory read + world->screen projection),
// hooks.cpp consumes it when drawing the overlay.  Keeping the two decoupled
// means the renderer never touches game memory and the reader never touches
// D3D state.
// ============================================================================
struct ESPBox {
    float left;
    float top;
    float right;
    float bottom;
    DWORD color;      // 0xAARRGGBB
    bool  isLocal;    // local player highlight
};

#define MAX_ESP_BOXES 64

extern ESPBox g_EspBoxes[MAX_ESP_BOXES];
extern volatile LONG g_EspBoxCount;

// Overlay surface size, published by the renderer every frame so the
// projection math can use the real back-buffer dimensions.
extern int g_ScreenWidth;
extern int g_ScreenHeight;
