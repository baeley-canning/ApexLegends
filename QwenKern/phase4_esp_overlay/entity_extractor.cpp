#define NOMINMAX
#include <Windows.h>
#include "entity_extractor.hpp"
#include "esp_renderer.hpp"  // For Team enum
#include <Psapi.h>
#include <TlHelp32.h>
#include <winternl.h>

#pragma comment(lib, "psapi.lib")

#include <algorithm>
#include <cstring>
#include <codecvt>

// ---------------------------------------------------------------------------
//  Process / window resolution helpers
// ---------------------------------------------------------------------------

static DWORD FindProcessIdByName(const wchar_t* process_name)
{
    DWORD pid = 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32W pe = {};
    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, process_name) == 0) {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return pid;
}

static HWND g_apexSearch = NULL;

static BOOL CALLBACK ApexEnumProc(HWND h, LPARAM)
{
    if (!IsWindowVisible(h)) return TRUE;

    wchar_t cls[256] = {};
    GetClassNameW(h, cls, 256);
    if (wcscmp(cls, L"Respawn001") == 0) { g_apexSearch = h; return FALSE; }

    wchar_t title[256] = {};
    GetWindowTextW(h, title, 256);
    if (wcsstr(title, L"Apex Legends")) { g_apexSearch = h; return FALSE; }

    return TRUE;
}

static HWND FindApexWindow()
{
    g_apexSearch = NULL;
    EnumWindows(ApexEnumProc, 0);
    return g_apexSearch;
}

// Resolve the main module (r5apex.exe) base address and image size by reading
// the remote process's PEB directly.  This is far more reliable than
// EnumProcessModulesEx/GetModuleInformation, which call ReadProcessMemory
// internally and can fail with ERROR_PARTIAL_COPY (299) when the target's
// module list changes mid-enumeration.
static bool ResolveModuleInfo(HANDLE process, uint64_t& out_base, SIZE_T& out_size)
{
    out_base = 0;
    out_size = 0;

    // NtQueryInformationProcess lives in ntdll.dll; resolve it dynamically so
    // we don't need to link against ntdll.lib.
    typedef LONG (NTAPI *NtQueryInformationProcess_t)(
        HANDLE, ULONG, PVOID, ULONG, PULONG);
    static NtQueryInformationProcess_t NtQIP = []() -> NtQueryInformationProcess_t {
        HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
        if (!ntdll) return nullptr;
        return (NtQueryInformationProcess_t)GetProcAddress(ntdll, "NtQueryInformationProcess");
    }();
    if (!NtQIP) return false;

    PROCESS_BASIC_INFORMATION pbi = {};
    ULONG retlen = 0;
    if (NtQIP(process, 0 /*ProcessBasicInformation*/, &pbi, sizeof(pbi), &retlen) != 0)
        return false;
    if (!pbi.PebBaseAddress) return false;

    // PEB->ImageBaseAddress is at offset 0x10 on x64.
    uint64_t image_base = 0;
    SIZE_T rd = 0;
    if (!ReadProcessMemory(process,
                           reinterpret_cast<LPCVOID>(reinterpret_cast<uint64_t>(pbi.PebBaseAddress) + 0x10),
                           &image_base, sizeof(image_base), &rd) || rd != sizeof(image_base))
        return false;
    if (!image_base) return false;

    // Read the PE headers to recover SizeOfImage.
    IMAGE_DOS_HEADER dos = {};
    rd = 0;
    if (!ReadProcessMemory(process, reinterpret_cast<LPCVOID>(image_base),
                           &dos, sizeof(dos), &rd) || rd != sizeof(dos))
        return false;
    if (dos.e_magic != IMAGE_DOS_SIGNATURE) return false;

    IMAGE_NT_HEADERS64 nt = {};
    rd = 0;
    if (!ReadProcessMemory(process,
                           reinterpret_cast<LPCVOID>(image_base + dos.e_lfanew),
                           &nt, sizeof(nt), &rd) || rd != sizeof(nt))
        return false;
    if (nt.Signature != IMAGE_NT_SIGNATURE) return false;
    if (nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;
    if (nt.OptionalHeader.SizeOfImage == 0) return false;

    out_base = image_base;
    out_size = nt.OptionalHeader.SizeOfImage;
    return true;
}

EntityExtractor::EntityExtractor()
    : process_handle_(nullptr), module_base_(0),
      entity_list_offset_(0), local_player_offset_(0) {
}

EntityExtractor::~EntityExtractor() {
    if (process_handle_) {
        CloseHandle(process_handle_);
    }
}

bool EntityExtractor::Initialize() {
    // Locate the Apex Legends process.  It can run as either r5apex.exe
    // (DX11) or r5apex_dx12.exe (DX12), so match both by name; fall back to
    // the Apex window if the process snapshot can't match either.
    DWORD process_id = FindProcessIdByName(L"r5apex.exe");
    if (!process_id) process_id = FindProcessIdByName(L"r5apex_dx12.exe");
    if (!process_id) {
        HWND apex = FindApexWindow();
        if (apex) GetWindowThreadProcessId(apex, &process_id);
    }
    if (!process_id) return false;

    process_handle_ = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
                                  FALSE, process_id);
    if (!process_handle_) return false;

    // Resolve the base module (r5apex.exe) and its image size via the PEB.
    SIZE_T module_size = 0;
    if (!ResolveModuleInfo(process_handle_, module_base_, module_size))
        return false;

    // Scan for entity list and local player pointers.
    // These patterns are based on Kernaim/Ignite/Chudvision signatures.
    const uint8_t* base = reinterpret_cast<const uint8_t*>(module_base_);

    // Entity list pattern: mov rax, [rip+XX] + mov rcx, [rax+XX]
    const char entity_list_pattern[] = "\x48\x8B\x05\x00\x00\x00\x00\x48\x8B\x48\x00";
    const char entity_list_mask[] = "xxx????xxxx";

    uint64_t entity_list_sig = ScanPattern(base, module_size,
                                           entity_list_pattern, entity_list_mask);
    if (entity_list_sig) {
        // RIP-relative target: the pointer variable sits at sig + 7 + disp32
        int32_t disp = *reinterpret_cast<const int32_t*>(base + entity_list_sig + 3);
        entity_list_offset_ = entity_list_sig + 7 + static_cast<uint64_t>(disp);
    }

    // Local player pattern: mov rax, [rip+XX] + test rax, rax
    const char local_player_pattern[] = "\x48\x8B\x05\x00\x00\x00\x00\x48\x85\xC0";
    const char local_player_mask[] = "xxx????xxxx";

    uint64_t local_player_sig = ScanPattern(base, module_size,
                                           local_player_pattern, local_player_mask);
    if (local_player_sig) {
        int32_t disp = *reinterpret_cast<const int32_t*>(base + local_player_sig + 3);
        local_player_offset_ = local_player_sig + 7 + static_cast<uint64_t>(disp);
    }

    return entity_list_offset_ != 0 && local_player_offset_ != 0;
}

EntityList EntityExtractor::ExtractEntities() {
    EntityList entity_list{};
    
    // Read entity list pointer
    uint64_t entity_list_addr = module_base_ + entity_list_offset_;
    uint64_t list_ptr = Read<uint64_t>(entity_list_addr);
    
    if (!list_ptr) {
        return entity_list;
    }
    
    entity_list.address = list_ptr;
    
    // Read entity count (offset 0x18 for Apex)
    entity_list.count = Read<uint32_t>(list_ptr + 0x18);
    entity_list.max_count = Read<uint32_t>(list_ptr + 0x1C);
    
    // Reserve space for players
    entity_list.players.reserve(entity_list.count);
    
    // Read all entities
    for (uint32_t i = 0; i < entity_list.count; ++i) {
        uint64_t entity_ptr = Read<uint64_t>(list_ptr + 0x28 + (i * 8));
        
        if (entity_ptr) {
            PlayerEntity player{};
            player.address = entity_ptr;
            player.base_entity = Read<uint64_t>(entity_ptr);
            
            // Read player name
            uint64_t name_ptr = Read<uint64_t>(entity_ptr + 0x58);
            player.player_name = ReadString(name_ptr);
            
            // Read account ID
            player.account_id = Read<uint32_t>(entity_ptr + 0x1D0);
            
            // Read position (offset 0x2A0 for Apex)
            player.position = Read<DirectX::XMFLOAT3>(entity_ptr + 0x2A0);
            
            // Read view angles
            player.view_angles = Read<DirectX::XMFLOAT3>(entity_ptr + 0x2BC);
            
            // Read health
            player.health = Read<uint32_t>(entity_ptr + 0x868);
            player.max_health = Read<uint32_t>(entity_ptr + 0x86C);
            
            // Read shield
            player.shield = Read<uint32_t>(entity_ptr + 0x970);
            player.max_shield = Read<uint32_t>(entity_ptr + 0x974);
            player.shield_cell_count = Read<uint32_t>(entity_ptr + 0x978);
            
            // Read team
            player.team = ReadTeam(entity_ptr);
            player.team_id = static_cast<uint8_t>(player.team);
            
            // Read state
            player.state = ReadPlayerState(entity_ptr);
            player.is_alive = IsAlive(player);
            
            // Read legend name
            player.legend_name = ReadLegendName(entity_ptr);
            player.legend_display_name = GetLegendDisplayName(player.legend_name);
            
            // Read movement info
            player.movement_speed = Read<float>(entity_ptr + 0x34C);
            player.stance = Read<uint32_t>(entity_ptr + 0x358);

            // Humanized config based on legend
            player.humanized_config = GetHumanizedConfig(player.legend_name);

            entity_list.players.push_back(player);
        }
    }
    
    // Identify local player and teammates
    uint64_t local_player_addr = module_base_ + local_player_offset_;
    uint64_t local_ptr = Read<uint64_t>(local_player_addr);
    
    for (auto& player : entity_list.players) {
        if (player.address == local_ptr) {
            player.is_local_player = true;
            entity_list.local_player = &player;
            
            // Teammates are those with same team_id and not self
            for (auto& other : entity_list.players) {
                if (&other != &player && other.team_id == player.team_id) {
                    other.is_teammate = true;
                    entity_list.teammates.push_back(&other);
                } else if (!other.is_local_player) {
                    entity_list.enemies.push_back(&other);
                }
            }
        }
    }
    
    return entity_list;
}

std::optional<PlayerEntity> EntityExtractor::GetLocalPlayer() {
    uint64_t local_player_addr = module_base_ + local_player_offset_;
    uint64_t local_ptr = Read<uint64_t>(local_player_addr);
    
    if (!local_ptr) {
        return std::nullopt;
    }
    
    PlayerEntity player{};
    player.address = local_ptr;
    player.base_entity = Read<uint64_t>(local_ptr);
    player.is_local_player = true;
    
    // Read all fields
    uint64_t name_ptr = Read<uint64_t>(local_ptr + 0x58);
    player.player_name = ReadString(name_ptr);
    player.account_id = Read<uint32_t>(local_ptr + 0x1D0);
    player.position = Read<DirectX::XMFLOAT3>(local_ptr + 0x2A0);
    player.view_angles = Read<DirectX::XMFLOAT3>(local_ptr + 0x2BC);
    player.health = Read<uint32_t>(local_ptr + 0x868);
    player.max_health = Read<uint32_t>(local_ptr + 0x86C);
    player.shield = Read<uint32_t>(local_ptr + 0x970);
    player.max_shield = Read<uint32_t>(local_ptr + 0x974);
    player.shield_cell_count = Read<uint32_t>(local_ptr + 0x978);
    player.team = ReadTeam(local_ptr);
    player.team_id = static_cast<uint8_t>(player.team);
    player.state = ReadPlayerState(local_ptr);
    player.legend_name = ReadLegendName(local_ptr);
    player.legend_display_name = EntityExtractor::GetLegendDisplayName(player.legend_name);
    player.movement_speed = Read<float>(local_ptr + 0x34C);
    player.stance = Read<uint32_t>(local_ptr + 0x358);
    player.humanized_config = GetHumanizedConfig(player.legend_name);
    
    return player;
}

std::optional<PlayerEntity> EntityExtractor::GetPlayerByIndex(uint32_t index) {
    uint64_t entity_list_addr = module_base_ + entity_list_offset_;
    uint64_t list_ptr = Read<uint64_t>(entity_list_addr);
    
    if (!list_ptr) {
        return std::nullopt;
    }
    
    uint64_t entity_ptr = Read<uint64_t>(list_ptr + 0x28 + (index * 8));
    
    if (!entity_ptr) {
        return std::nullopt;
    }
    
    PlayerEntity player{};
    player.address = entity_ptr;
    player.base_entity = Read<uint64_t>(entity_ptr);
    
    uint64_t name_ptr = Read<uint64_t>(entity_ptr + 0x58);
    player.player_name = ReadString(name_ptr);
    player.account_id = Read<uint32_t>(entity_ptr + 0x1D0);
    player.position = Read<DirectX::XMFLOAT3>(entity_ptr + 0x2A0);
    player.view_angles = Read<DirectX::XMFLOAT3>(entity_ptr + 0x2BC);
    player.health = Read<uint32_t>(entity_ptr + 0x868);
    player.max_health = Read<uint32_t>(entity_ptr + 0x86C);
    player.shield = Read<uint32_t>(entity_ptr + 0x970);
    player.max_shield = Read<uint32_t>(entity_ptr + 0x974);
    player.shield_cell_count = Read<uint32_t>(entity_ptr + 0x978);
    player.team = ReadTeam(entity_ptr);
    player.team_id = static_cast<uint8_t>(player.team);
    player.state = ReadPlayerState(entity_ptr);
    player.legend_name = ReadLegendName(entity_ptr);
    player.legend_display_name = EntityExtractor::GetLegendDisplayName(player.legend_name);
    player.movement_speed = Read<float>(entity_ptr + 0x34C);
    player.stance = Read<uint32_t>(entity_ptr + 0x358);
    player.humanized_config = GetHumanizedConfig(player.legend_name);
    
    return player;
}

std::optional<PlayerEntity> EntityExtractor::GetPlayerByName(const std::string& name) {
    auto entities = ExtractEntities();
    
    auto it = std::find_if(entities.players.begin(), entities.players.end(),
        [&name](const PlayerEntity& p) { 
            return p.player_name == name || p.legend_display_name == name; 
        });
    
    if (it != entities.players.end()) {
        return *it;
    }
    
    return std::nullopt;
}

std::vector<PlayerEntity> EntityExtractor::GetEnemies() {
    auto entities = ExtractEntities();
    std::vector<PlayerEntity> result;
    result.reserve(entities.enemies.size());
    for (auto* enemy : entities.enemies) {
        result.push_back(*enemy);
    }
    return result;
}

std::vector<PlayerEntity> EntityExtractor::GetTeammates() {
    auto entities = ExtractEntities();
    std::vector<PlayerEntity> result;
    result.reserve(entities.teammates.size());
    for (auto* teammate : entities.teammates) {
        result.push_back(*teammate);
    }
    return result;
}

std::string EntityExtractor::ReadString(uint64_t address, size_t max_length) {
    std::string result{};
    char buffer[256]{};
    
    size_t read_size = std::min(max_length, sizeof(buffer));
    ReadProcessMemory(process_handle_, reinterpret_cast<LPCVOID>(address), 
                      buffer, read_size, nullptr);
    
    // Handle UTF-8 strings
    result = std::string(buffer, strnlen_s(buffer, read_size));
    
    return result;
}

bool EntityExtractor::IsAlive(const PlayerEntity& player) {
    return player.state == PlayerState::ALIVE || 
           player.state == PlayerState::SPAWNING;
}

bool EntityExtractor::IsDead(const PlayerEntity& player) {
    return player.state == PlayerState::DYING || 
           player.state == PlayerState::DEAD;
}

DirectX::XMFLOAT3 EntityExtractor::GetTeamColor(Team team, bool use_glow) {
    // Kernaim-style team colors with glow support
    static const DirectX::XMFLOAT3 team_colors[] = {
        {1.0f, 0.2f, 0.2f},   // RED - Bright red
        {0.2f, 0.4f, 1.0f},   // BLUE - Sky blue
        {0.2f, 0.8f, 0.3f},   // GREEN - Emerald
        {1.0f, 0.6f, 0.2f},   // ORANGE - Amber
        {0.7f, 0.3f, 0.9f},   // PURPLE - Royal
        {1.0f, 0.9f, 0.2f},   // YELLOW - Gold
        {0.2f, 0.8f, 0.8f},   // TEAL - Cyan
        {1.0f, 0.3f, 0.6f},   // PINK - Rose
    };
    
    static const DirectX::XMFLOAT3 team_glow_colors[] = {
        {1.0f, 0.4f, 0.2f},   // RED glow
        {0.4f, 0.6f, 1.0f},   // BLUE glow
        {0.4f, 0.9f, 0.5f},   // GREEN glow
        {1.0f, 0.7f, 0.4f},   // ORANGE glow
        {0.9f, 0.5f, 1.0f},   // PURPLE glow
        {1.0f, 1.0f, 0.4f},   // YELLOW glow
        {0.4f, 0.9f, 0.9f},   // TEAL glow
        {1.0f, 0.5f, 0.7f},   // PINK glow
    };
    
    auto color = team_colors[static_cast<int>(team)];
    
    if (use_glow) {
        color = team_glow_colors[static_cast<int>(team)];
    }
    
    return color;
}

std::string EntityExtractor::GetLegendDisplayName(LegendName name) {
    static const char* legend_names[] = {
        "Alias",      // ALIAS
        "Angel",      // ANGEL
        "Apox",       // APOX
        "Ash",        // ASH
        "Bangarang",  // BANGARANG
        "Benedict",   // BENEDICT
        "Caustic",    // CAUSTIC
        "Cody",       // CODY
        "Dash",       // DASH
        "Echo",       // ECHO
        "Fisher",     // FISHERMAN
        "Gladstone",  // GLADSTONE
        "Griffin",    // GRIFFIN
        "Huntsman",   // HUNTSMAN
        "Ibtida",     // IBTIDA
        "Jurisdiction", // JURISDICION
        "Kanima",     // KANIMA
        "Lifeline",   // LIFELINE
        "Loba",       // LOBA
        "Mirage",     // MIRAGE
        "Nemesis",    // NEMESIS
        "Noob",       // NOOB
        "Parish",     // PARISH
        "Reaper",     // REAPER
        "Rental",     // RENTAL
        "Ronin",      // RONIN
        "Samurai",    // SAMURAI
        "Scorpion",   // SCORPION
        "Shadow",     // SHADOW
        "Simulacrum", // SIMULACRUM
        "Smoke",      // SMOKE
        "Spark",      // SPARK
        "Stalwart",   // STALWART
        "Tactician",  // TACTICIAN
        "Trax",       // TRAX
        "Vanguard",   // VANGUARD
        "Vantage",    // VANTAGE
        "Velocity",   // VELOCITY
        "Wattson",    // WATTSON
        "Wraith",     // WRAITH
        "Zappa",      // ZAPPA
    };
    
    return legend_names[static_cast<int>(name)];
}

HumanizedConfig EntityExtractor::GetHumanizedConfig(LegendName name) {
    HumanizedConfig config{};
    
    // Kernaim/Ignite/Chudvision humanized patterns
    switch (name) {
        case LegendName::WRAITH:
            // Wraith: tight hitbox, harder to hit, faster movement
            config = {true, false, 1.0f, 0.85f};
            break;
        case LegendName::GRIFFIN:
            // Griffin: loose hitbox, easier to hit but has shield regen
            config = {false, true, 1.1f, 0.9f};
            break;
        case LegendName::CAUSTIC:
            // Caustic: tight with gas mitigation
            config = {true, false, 0.95f, 0.9f};
            break;
        case LegendName::MIRAGE:
            // Mirage: loose with decoys
            config = {false, true, 1.0f, 0.8f};
            break;
        case LegendName::REAPER:
            // Reaper: tight for sniping
            config = {true, false, 1.05f, 0.95f};
            break;
        case LegendName::WATTSON:
            // Wattson: tight with shield regen
            config = {true, false, 0.9f, 0.85f};
            break;
        case LegendName::LIFELINE:
            // Lifeline: loose with healing
            config = {false, true, 1.1f, 0.8f};
            break;
        case LegendName::VANGUARD:
            // Vanguard: medium tight for tanking
            config = {true, false, 1.2f, 1.0f};
            break;
        default:
            // Default: balanced
            config = {false, false, 1.0f, 1.0f};
            break;
    }
    
    return config;
}

uint64_t EntityExtractor::ScanPattern(const uint8_t* data, size_t size,
                                      const char* pattern, const char* mask) {
    size_t pattern_len = strlen(mask);
    
    for (size_t i = 0; i < size - pattern_len; ++i) {
        bool found = true;
        for (size_t j = 0; j < pattern_len; ++j) {
            if (!(mask[j] == '?' || data[i + j] == pattern[j])) {
                found = false;
                break;
            }
        }
        
        if (found) {
            return static_cast<uint64_t>(i);
        }
    }
    
    return 0;
}

PlayerState EntityExtractor::ReadPlayerState(uint64_t address) {
    uint32_t state = Read<uint32_t>(address + 0x10);
    return static_cast<PlayerState>(state);
}

Team EntityExtractor::ReadTeam(uint64_t address) {
    uint8_t team_id = Read<uint8_t>(address + 0x45C);
    
    // Team mapping in Apex: RED=0, BLUE=1, GREEN=2, etc.
    switch (team_id % 8) {
        case 0: return Team::RED;
        case 1: return Team::BLUE;
        case 2: return Team::GREEN;
        case 3: return Team::ORANGE;
        case 4: return Team::PURPLE;
        case 5: return Team::YELLOW;
        case 6: return Team::TEAL;
        case 7: return Team::PINK;
        default: return Team::RED;
    }
}

LegendName EntityExtractor::ReadLegendName(uint64_t address) {
    uint32_t legend_index = Read<uint32_t>(address + 0x468);
    
    // Map legend index to LegendName enum
    if (legend_index < 41) {
        return static_cast<LegendName>(legend_index);
    }
    
    return LegendName::NOOB;
}

float EntityExtractor::CalculateDistance(const DirectX::XMFLOAT3& a,
                                         const DirectX::XMFLOAT3& b) {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dz = a.z - b.z;
    
    return sqrtf(dx * dx + dy * dy + dz * dz);
}
