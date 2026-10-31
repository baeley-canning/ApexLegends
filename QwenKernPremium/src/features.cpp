#include "features.h"
#include "memory.h"
#include "log.h"

#include <cmath>
#include <cstring>

// ============================================================================
// Global state (declared in features.h)
// ============================================================================
CheatFeatures*   g_pCheatFeatures = nullptr;
ESPBox           g_EspBoxes[MAX_ESP_BOXES] = {};
volatile LONG    g_EspBoxCount = 0;
int              g_ScreenWidth  = 1920;
int              g_ScreenHeight = 1080;

namespace {

// ----------------------------------------------------------------------------
// CANDIDATE structure offsets.
//
// Only three offsets are documented in docs/ (ENTITY_LIST, LOCAL_PLAYER,
// VIEW_MATRIX); the per-entity members below are typical Apex layouts and MUST
// be re-validated with OffsetValidator + a live match.  They are kept in one
// place so a patch only requires editing this block.
// ----------------------------------------------------------------------------
constexpr DWORD OFF_ENTITY_ORIGIN = 0x0258;   // Vec3 world position
constexpr DWORD OFF_ENTITY_TEAM   = 0x0478;   // int32 team id
constexpr DWORD OFF_ENTITY_HEALTH = 0x03A0;   // int32 health

constexpr int   MAX_ENTITIES     = 128;

constexpr DWORD COLOR_ENEMY  = 0xFFFF4040;    // AARRGGBB
constexpr DWORD COLOR_TEAM   = 0xFF40FF40;
constexpr DWORD COLOR_LOCAL  = 0xFFFFD040;

struct Vec3 {
    float x;
    float y;
    float z;
};

// Standard row-major view-projection transform.
// depthOut receives the view-space w (distance along the view axis).
bool WorldToScreen(const float* matrix, const Vec3& world,
                   float& screenX, float& screenY, float& depthOut) {
    const float w = matrix[3] * world.x + matrix[7] * world.y +
                    matrix[11] * world.z + matrix[15];
    if (w < 0.001f) return false;              // behind the camera

    const float invW = 1.0f / w;
    const float ndcX = (matrix[0] * world.x + matrix[4] * world.y +
                        matrix[8] * world.z + matrix[12]) * invW;
    const float ndcY = (matrix[1] * world.x + matrix[5] * world.y +
                        matrix[9] * world.z + matrix[13]) * invW;

    screenX = (static_cast<float>(g_ScreenWidth)  * 0.5f) * (1.0f + ndcX);
    screenY = (static_cast<float>(g_ScreenHeight) * 0.5f) * (1.0f - ndcY);
    depthOut = w;

    return screenX > -4096.0f && screenX < static_cast<float>(g_ScreenWidth) + 4096.0f &&
           screenY > -4096.0f && screenY < static_cast<float>(g_ScreenHeight) + 4096.0f;
}

template <typename T>
bool ReadValue(MemoryReader* reader, DWORD64 address, T& out) {
    auto raw = reader->ReadArray(reinterpret_cast<LPVOID>(address), sizeof(T));
    if (raw.size() != sizeof(T)) return false;
    std::memcpy(&out, raw.data(), sizeof(T));
    return true;
}

float ClampFloat(float value, float low, float high) {
    if (value < low)  return low;
    if (value > high) return high;
    return value;
}

} // namespace

CheatFeatures::CheatFeatures() {
    // Initialize all features as disabled by default
    for (int i = 0; i < 4; ++i) {
        featuresEnabled[i] = false;
    }
    
    // Feature-specific settings
    aimbotSmoothness = 1.0f;
    bDrawLines = true;
    bDrawBoxes = true;
    bDrawNames = true;
}


void CheatFeatures::EnableFeature(FeatureType type, bool enable) {
    if (type >= FEATURE_AIMBOT && type <= FEATURE_RECOIL) {
        featuresEnabled[type] = enable;
    }
}

bool CheatFeatures::IsFeatureEnabled(FeatureType type) const {
    if (type >= FEATURE_AIMBOT && type <= FEATURE_RECOIL) {
        return featuresEnabled[type];
    }
    return false;
}

void CheatFeatures::UpdateAimbot(MemoryReader* reader) {
    if (!IsFeatureEnabled(FEATURE_AIMBOT) || !reader)
        return;
        
    // TODO: Implement actual aimbot logic
    // This would involve:
    // 1. Reading player positions from memory
    // 2. Calculating angles to target players
    // 3. Applying smoothness/acceleration
    // 4. Writing back to game's input system
    
    // Placeholder implementation
}

void CheatFeatures::UpdateESP(MemoryReader* reader) {
    InterlockedExchange(&g_EspBoxCount, 0);

    if (!IsFeatureEnabled(FEATURE_ESP) || !reader)
        return;

    // r5apex.exe base is resolved once (cheap) and cached: the module never
    // moves within a process lifetime.  GetGameModuleBase() also accepts
    // r5apex_dx12.exe, which is the binary we are actually injected into.
    static DWORD64 moduleBase = 0;
    static bool loggedModule = false;
    if (moduleBase == 0) {
        moduleBase = reader->GetGameModuleBase();
        if (moduleBase == 0) {
            // Latched: UpdateESP runs every frame and must not spam the log.
            if (!loggedModule) {
                loggedModule = true;
                Logf("[!] esp: game module base not found (r5apex_dx12.exe / r5apex.exe)");
            }
            return;
        }
        if (!loggedModule) {
            loggedModule = true;
            Logf("[*] esp: game module base = 0x%llX",
                 static_cast<unsigned long long>(moduleBase));
        }
    }

    // ---- view matrix -------------------------------------------------------
    float view[16] = { 0.0f };
    {
        auto raw = reader->ReadArray(
            reinterpret_cast<LPVOID>(moduleBase + ApexOffsets::VIEW_MATRIX), sizeof(view));
        if (raw.size() != sizeof(view)) return;
        std::memcpy(view, raw.data(), sizeof(view));

        // Same canary as OffsetValidator: the documented RVA may point at code.
        for (int i = 0; i < 16; ++i) {
            if (!std::isfinite(view[i])) return;
        }
        if (view[15] == 0.0f) return;
    }

    // ---- entity list -------------------------------------------------------
    DWORD64 entityList = 0;
    if (!ReadValue(reader, moduleBase + ApexOffsets::ENTITY_LIST, entityList) ||
        entityList < 0x10000) {
        return;
    }

    // ---- local player (used for team colouring) ---------------------------
    DWORD64 localPlayer = 0;
    int localTeam = -1;
    if (ReadValue(reader, moduleBase + ApexOffsets::LOCAL_PLAYER, localPlayer) &&
        localPlayer > 0x10000) {
        ReadValue(reader, localPlayer + OFF_ENTITY_TEAM, localTeam);
    }

    // ---- walk the list, project, publish boxes ---------------------------
    int boxCount = 0;
    for (int i = 0; i < MAX_ENTITIES && boxCount < MAX_ESP_BOXES; ++i) {
        DWORD64 entity = 0;
        if (!ReadValue(reader, entityList + static_cast<DWORD64>(i) * sizeof(void*), entity))
            continue;
        if (entity < 0x10000) continue;

        Vec3 origin{};
        if (!ReadValue(reader, entity + OFF_ENTITY_ORIGIN, origin)) continue;
        if (!std::isfinite(origin.x) || !std::isfinite(origin.y) ||
            !std::isfinite(origin.z)) {
            continue;
        }
        // Skip uninitialised entities parked at the world origin.
        if (std::fabs(origin.x) < 1.0f && std::fabs(origin.y) < 1.0f &&
            std::fabs(origin.z) < 1.0f) {
            continue;
        }

        int health = 0;
        ReadValue(reader, entity + OFF_ENTITY_HEALTH, health);
        if (health <= 0 || health > 200) continue;   // dead / not a player

        float screenX = 0.0f;
        float screenY = 0.0f;
        float depth = 0.0f;
        if (!WorldToScreen(view, origin, screenX, screenY, depth)) continue;
        if (depth <= 0.1f) continue;

        // Perspective size: closer entities get bigger boxes.
        const float boxHeight = ClampFloat(2400.0f / depth, 24.0f, 420.0f);
        const float boxWidth  = boxHeight * 0.45f;

        int team = -1;
        ReadValue(reader, entity + OFF_ENTITY_TEAM, team);

        DWORD color = COLOR_ENEMY;
        if (localTeam >= 0 && team == localTeam) {
            color = COLOR_TEAM;
        }

        ESPBox& box = g_EspBoxes[boxCount];
        box.left   = screenX - boxWidth * 0.5f;
        box.top    = screenY - boxHeight;
        box.right  = screenX + boxWidth * 0.5f;
        box.bottom = screenY;
        box.color  = color;
        box.isLocal = false;

        ++boxCount;
    }

    InterlockedExchange(&g_EspBoxCount, static_cast<LONG>(boxCount));
}


void CheatFeatures::UpdateGlow(MemoryReader* reader) {
    if (!IsFeatureEnabled(FEATURE_GLOW) || !reader)
        return;
        
    // TODO: Implement glow effect logic
    // This would involve:
    // 1. Reading glow object pointers from memory
    // 2. Setting glow colors and intensity
    // 3. Applying to players/items
    
    // Placeholder implementation
}

void CheatFeatures::UpdateRecoilCompensation(MemoryReader* reader) {
    if (!IsFeatureEnabled(FEATURE_RECOIL) || !reader)
        return;
        
    // TODO: Implement recoil compensation logic
    // This would involve:
    // 1. Reading weapon/shot data from memory
    // 2. Calculating and applying recoil patterns
    
    // Placeholder implementation
}