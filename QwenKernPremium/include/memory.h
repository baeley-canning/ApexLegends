#pragma once
#include <windows.h>
#include <vector>

class MemoryReader {
private:
    HANDLE hProcess;
    DWORD processId;
    
public:
    MemoryReader();
    ~MemoryReader();
    
    bool Initialize(DWORD pid);
    void Cleanup();
    
    // Read memory functions
    template<typename T>
    T ReadMemory(LPVOID address) {
        T value = T{};
        ReadProcessMemory(hProcess, address, &value, sizeof(T), nullptr);
        return value;
    }
    
    template<typename T>
    bool WriteMemory(LPVOID address, const T& value) {
        return WriteProcessMemory(hProcess, address, &value, sizeof(T), nullptr);
    }
    
    // Read array of data
    std::vector<BYTE> ReadArray(LPVOID address, size_t length);
    
    // Utility functions
    bool IsAddressValid(LPVOID address);

    // DWORD64, not DWORD: an x64 module base (e.g. 0x7FF6...) does not fit in
    // 32 bits; returning DWORD silently truncated it (C4244 + broken pointers).
    DWORD64 GetModuleBase(const char* moduleName);

    // Base of the game image, whichever build we are injected into:
    // "r5apex_dx12.exe" (what the launcher starts today) or the older
    // "r5apex.exe".  Looking up "r5apex.exe" by name inside the DX12 process
    // returns 0, and every ApexOffsets RVA is then read from +0 (garbage), so
    // ESP silently published zero boxes.  Never returns 0 without also being
    // genuinely absent from the process.
    DWORD64 GetGameModuleBase();
};

// ============================================================================
// Apex Legends (r5apex.exe) — Known Offset Constants
// Based on RE findings from CasualX/apexdream, CheatOffsets, eastarcti.ca
// Offsets are RELATIVE to r5apex.exe base address (not absolute).
// These values drift with each game patch and should be validated at runtime.
// ============================================================================

namespace ApexOffsets {
    // Entity list pointer offset (relative to r5apex.exe base)
    constexpr DWORD ENTITY_LIST = 0x23F6A90;
    
    // Local player base offset (relative to r5apex.exe base)
    constexpr DWORD LOCAL_PLAYER = 0x01E7D4B8;
    
    // View matrix / engine trace client offset (VTP_GetEngineTraceClient: 0x22ee01)
    constexpr DWORD VIEW_MATRIX = 0x022EE01;
    
    // R5AC monitored VMT hook points (RVAs in r5apex.exe):
    namespace R5AC_VMT {
        constexpr DWORD GET_ENGINE_TRACE_CLIENT     = 0x22ee01;
        constexpr DWORD GET_FILESYSTEM_INTERFACE    = 0x479351;
        constexpr DWORD C_PLAYER_SPAWN              = 0x817371;
        constexpr DWORD GET_ENTITY_LIST             = 0x865491;
        constexpr DWORD GET_VIEW_RENDER_INSTANCE    = 0x9f13b1;
    }
    
    // R5AC module whitelist (RVAs within whitelisted modules):
    namespace Whitelist {
        constexpr DWORD R5APEX_MIN = 0x1000;
        constexpr DWORD R5APEX_MAX = 0x13d2000;      // .text section
        constexpr DWORD KERNEL32_MAX = 0x7f4bb;       // .text section  
        constexpr DWORD NTDLL_MAX = 0x119f1e;         // .text section
    }
}
