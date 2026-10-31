#pragma once
#ifndef ENTITY_EXTRACTOR_HPP
#define ENTITY_EXTRACTOR_HPP

#include <Windows.h>
#include <DirectXMath.h>
#include <cstdint>
#include <vector>
#include <string>
#include <optional>

// Forward declarations
struct PlayerEntity;
struct EntityList;

// Player state enumeration matching Apex Legends engine
enum class PlayerState : uint32_t {
    NONE = 0,
    ALIVE = 1,
    DYING = 2,
    DEAD = 3,
    SPAWNING = 4,
};

// Legend name enumeration
enum class LegendName : uint8_t {
    ALIAS = 0,
    ANGEL = 1,
    APOX = 2,
    ASH = 3,
    BANGARANG = 4,
    BENEDICT = 5,
    CAUSTIC = 6,
    CODY = 7,
    DASH = 8,
    ECHO = 9,
    FISHERMAN = 10,
    GLADSTONE = 11,
    GRIFFIN = 12,
    HUNTSMAN = 13,
    IBTIDA = 14,
    JURISDICION = 15,
    KANIMA = 16,
    LIFELINE = 17,
    LOBA = 18,
    MIRAGE = 19,
    NEMESIS = 20,
    NOOB = 21,
    PARISH = 22,
    REAPER = 23,
    RENTAL = 24,
    RONIN = 25,
    SAMURAI = 26,
    SCORPION = 27,
    SHADOW = 28,
    SIMULACRUM = 29,
    SMOKE = 30,
    SPARK = 31,
    STALWART = 32,
    TACTICIAN = 33,
    TRAX = 34,
    VANGUARD = 35,
    VANTAGE = 36,
    VELOCITY = 37,
    WATTSON = 38,
    WRAITH = 39,
    ZAPPA = 40,
};

// Team enumeration for player classification (matching esp_renderer.hpp)
enum class Team : uint8_t {
    RED = 0,
    BLUE = 1,
    GREEN = 2,
    ORANGE = 3,
    PURPLE = 4,
    YELLOW = 5,
    TEAL = 6,
    PINK = 7,
};

// Humanized config structure (Wraith tight, Gibraltar loose, etc.)
// Defined before EntityExtractor to be usable in PlayerEntity
struct HumanizedConfig {
    bool is_tight;
    bool is_loose;
    float damage_mult;
    float recoil_mult;
};

// Player entity structure representing a single player in the game
struct PlayerEntity {
    uint64_t address;
    uint64_t base_entity;
    
    // Identity
    LegendName legend_name;
    std::string legend_display_name;
    std::string player_name;
    uint32_t account_id;
    
    // Position and orientation
    DirectX::XMFLOAT3 position;
    DirectX::XMFLOAT3 view_angles;
    float FOV;
    
    // Combat stats
    uint32_t health;
    uint32_t max_health;
    uint32_t shield;
    uint32_t max_shield;
    uint32_t shield_cell_count;
    
    // Team info
    Team team;
    uint8_t team_id;
    bool is_teammate;
    
    // State
    PlayerState state;
    bool is_local_player;
    bool is_alive;
    
    // Movement
    float movement_speed;
    uint32_t stance;  // 0=stand, 1=crouch, 2=prone
    
    // Rendering info for ESP
    DirectX::XMFLOAT2 screen_position;
    float screen_width;
    float screen_height;
    float distance_to_player;

    // Humanized features (Wraith tight, Gibraltar loose, etc.)
    HumanizedConfig humanized_config;
};

// Entity list structure containing all entities in the game
struct EntityList {
    uint64_t address;
    uint32_t count;
    uint32_t max_count;
    std::vector<PlayerEntity> players;
    
    // Cached pointers for fast access
    PlayerEntity* local_player = nullptr;
    std::vector<PlayerEntity*> enemies;
    std::vector<PlayerEntity*> teammates;
};

// Entity extractor class for reading Apex Legends memory
class EntityExtractor {
public:
    EntityExtractor();
    ~EntityExtractor();
    
    // Initialize the entity extractor.  Resolves the Apex Legends process
    // (r5apex.exe) and its base module internally, then scans for the entity
    // list and local player pointers.
    bool Initialize();
    
    // Extract all entities from the game
    EntityList ExtractEntities();
    
    // Get local player entity
    std::optional<PlayerEntity> GetLocalPlayer();
    
    // Get player by index
    std::optional<PlayerEntity> GetPlayerByIndex(uint32_t index);
    
    // Get player by name
    std::optional<PlayerEntity> GetPlayerByName(const std::string& name);
    
    // Get all enemies (non-teammates)
    std::vector<PlayerEntity> GetEnemies();
    
    // Get all teammates
    std::vector<PlayerEntity> GetTeammates();
    
    // Read memory with error handling
    template<typename T>
    T Read(uint64_t address) {
        T value{};
        if (ReadProcessMemory(process_handle_, reinterpret_cast<LPCVOID>(address), 
                              &value, sizeof(T), nullptr)) {
            return value;
        }
        return {};
    }
    
    // Read string from memory
    std::string ReadString(uint64_t address, size_t max_length = 64);
    
    // Check if player is alive
    static bool IsAlive(const PlayerEntity& player);
    
    // Check if player is dead
    static bool IsDead(const PlayerEntity& player);
    
    // Get team color for rendering
    static DirectX::XMFLOAT3 GetTeamColor(Team team, bool use_glow = false);
    
    // Get legend display name
    static std::string GetLegendDisplayName(LegendName name);

    // Get humanized config based on legend
    static HumanizedConfig GetHumanizedConfig(LegendName name);

private:
    HANDLE process_handle_;
    uint64_t module_base_;
    uint64_t entity_list_offset_;
    uint64_t local_player_offset_;
    
    // Pattern scanning helpers
    uint64_t ScanPattern(const uint8_t* data, size_t size, 
                         const char* pattern, const char* mask);
    
    // Read player state from memory
    PlayerState ReadPlayerState(uint64_t address);
    
    // Read team information
    Team ReadTeam(uint64_t address);
    
    // Read legend name
    LegendName ReadLegendName(uint64_t address);
    
    // Calculate distance between two players
    static float CalculateDistance(const DirectX::XMFLOAT3& a, 
                                    const DirectX::XMFLOAT3& b);
};

#endif // ENTITY_EXTRACTOR_HPP
