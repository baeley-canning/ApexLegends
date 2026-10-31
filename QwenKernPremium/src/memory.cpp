#include "memory.h"
#include <psapi.h>
#include <string>

MemoryReader::MemoryReader() : hProcess(nullptr), processId(0) {
}

MemoryReader::~MemoryReader() {
    Cleanup();
}

bool MemoryReader::Initialize(DWORD pid) {
    if (hProcess != nullptr)
        return true;
        
    processId = pid;
    hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    
    return hProcess != nullptr;
}

void MemoryReader::Cleanup() {
    if (hProcess != nullptr) {
        CloseHandle(hProcess);
        hProcess = nullptr;
        processId = 0;
    }
}

std::vector<BYTE> MemoryReader::ReadArray(LPVOID address, size_t length) {
    std::vector<BYTE> buffer(length);
    
    if (ReadProcessMemory(hProcess, address, buffer.data(), length, nullptr)) {
        return buffer;
    }
    
    // Return empty vector on failure
    return {};
}

bool MemoryReader::IsAddressValid(LPVOID address) {
    if (!address || !hProcess)
        return false;
        
    DWORD oldProtect = 0;
    return VirtualProtectEx(hProcess, address, 1, PAGE_EXECUTE_READWRITE, &oldProtect);
}

DWORD64 MemoryReader::GetModuleBase(const char* moduleName) {
    if (!hProcess || !moduleName)
        return 0;
        
    HMODULE hMods[1024];
    DWORD cbNeeded = 0;
    
    if (EnumProcessModules(hProcess, hMods, sizeof(hMods), &cbNeeded)) {
        for (unsigned int i = 0; i < (cbNeeded / sizeof(HMODULE)); i++) {
            char szModName[MAX_PATH];
            
            if (GetModuleFileNameExA(hProcess, hMods[i], szModName, sizeof(szModName))) {
                // Extract just the module name
                std::string fullModuleName = szModName;
                size_t pos = fullModuleName.find_last_of("\\/");
                
                if (pos != std::string::npos) {
                    std::string moduleNameOnly = fullModuleName.substr(pos + 1);
                    
                    if (moduleNameOnly == moduleName) {
                        return reinterpret_cast<DWORD64>(hMods[i]);
                    }
                }
            }
        }
    }
    
    return 0;
}

DWORD64 MemoryReader::GetGameModuleBase() {
    // Order matters: prefer the DX12 build (the one the launcher starts) so a
    // process that somehow hosts both images resolves deterministically.
    static const char* const kGameModules[] = {
        "r5apex_dx12.exe", "r5apex.exe"
    };

    for (size_t i = 0; i < sizeof(kGameModules) / sizeof(kGameModules[0]); ++i) {
        const DWORD64 base = GetModuleBase(kGameModules[i]);
        if (base != 0)
            return base;
    }

    return 0;
}