#include "offset_validator.h"
#include "memory.h"

#include <cstdio>
#include <cmath>
#include <cstring>

// ============================================================================
// OffsetValidator
//
// Purpose: r5apex.exe offsets drift every patch (and Apex patches weekly), so
// the cheat must never trust a hardcoded constant blindly.  Every check below
// is a *readability + plausibility* probe against the live process:
//   - is the address committed and readable?
//   - does the value look like a pointer inside user space?
//   - does the matrix look like a matrix at all?
// A failing check does not crash the renderer; it disables the dependent
// feature and reports why.
// ============================================================================

namespace {

bool IsReadable(HANDLE hProcess, DWORD64 address, SIZE_T size) {
    if (!hProcess || address == 0 || size == 0) return false;

    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQueryEx(hProcess, reinterpret_cast<LPCVOID>(address), &mbi, sizeof(mbi))
        != sizeof(mbi)) {
        return false;
    }
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;

    const DWORD64 regionStart = reinterpret_cast<DWORD64>(mbi.BaseAddress);
    const DWORD64 regionEnd   = regionStart + mbi.RegionSize;
    return (address + size) <= regionEnd;
}

bool ReadBytes(HANDLE hProcess, DWORD64 address, void* out, SIZE_T size) {
    if (!IsReadable(hProcess, address, size)) return false;

    SIZE_T bytesRead = 0;
    return ReadProcessMemory(hProcess, reinterpret_cast<LPCVOID>(address),
                             out, size, &bytesRead) && bytesRead == size;
}

bool ReadPointer(HANDLE hProcess, DWORD64 address, DWORD64& value) {
    value = 0;
    return ReadBytes(hProcess, address, &value, sizeof(value)) && value != 0;
}

bool LooksLikeUserPointer(DWORD64 value) {
    // x64 user space ends at 0x00007FFFFFFFFFFF; also reject low/unaligned junk.
    return value >= 0x10000 && value <= 0x00007FFFFFFFFFFFULL;
}

ValidationResult MakeResult(const char* name, bool valid, DWORD64 actual,
                            const std::string& error) {
    ValidationResult result{};
    result.name = name ? name : "";
    result.valid = valid;
    result.actualValue = actual;
    result.errorMessage = error;
    return result;
}

std::string HexText(DWORD64 value) {
    char buffer[32] = { 0 };
    sprintf_s(buffer, sizeof(buffer), "0x%llX",
              static_cast<unsigned long long>(value));
    return std::string(buffer);
}

} // namespace

OffsetValidator::OffsetValidator() : hProcess_(nullptr), moduleBase_(0) {
}

bool OffsetValidator::Initialize(HANDLE hProcess, DWORD64 moduleBase) {
    hProcess_   = hProcess;
    moduleBase_ = moduleBase;

    if (!hProcess_ || moduleBase_ == 0) return false;

    // Sanity check the module base by validating the PE headers.  A stale or
    // wrong base is the single most common cause of "nothing works" reports.
    IMAGE_DOS_HEADER dosHeader{};
    if (!ReadBytes(hProcess_, moduleBase_, &dosHeader, sizeof(dosHeader))) return false;
    if (dosHeader.e_magic != IMAGE_DOS_SIGNATURE) return false;

    IMAGE_NT_HEADERS64 ntHeaders{};
    const DWORD64 ntAddress = moduleBase_ + static_cast<DWORD64>(dosHeader.e_lfanew);
    if (!ReadBytes(hProcess_, ntAddress, &ntHeaders, sizeof(ntHeaders))) return false;
    if (ntHeaders.Signature != IMAGE_NT_SIGNATURE) return false;
    if (ntHeaders.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;

    return true;
}

std::vector<ValidationResult> OffsetValidator::ValidateAll() {
    std::vector<ValidationResult> results;

    if (!hProcess_ || moduleBase_ == 0) {
        results.push_back(MakeResult("ModuleBase", false, moduleBase_,
                                     "OffsetValidator not initialized"));
        return results;
    }

    // Initialize() already verified the PE headers, so the base is good here.
    results.push_back(MakeResult("ModuleBase", true, moduleBase_, ""));

    results.push_back(ValidateEntityListPointer());
    results.push_back(ValidateLocalPlayerAccess());
    results.push_back(ValidateViewMatrixRead());
    results.push_back(ValidateR5ACVMTIntegrity());

    return results;
}

// ----------------------------------------------------------------------------
// moduleBase + ENTITY_LIST (0x23F6A90) must hold a pointer, and that pointer
// must be walkable (the head entry is itself a pointer).
// ----------------------------------------------------------------------------
ValidationResult OffsetValidator::ValidateEntityListPointer() {
    const DWORD64 slot = moduleBase_ + ApexOffsets::ENTITY_LIST;

    DWORD64 entityList = 0;
    if (!ReadPointer(hProcess_, slot, entityList)) {
        return MakeResult("EntityList", false, 0,
                          "no readable pointer at moduleBase+" +
                          HexText(ApexOffsets::ENTITY_LIST));
    }
    if (!LooksLikeUserPointer(entityList)) {
        return MakeResult("EntityList", false, entityList,
                          "value is not a plausible user-space pointer");
    }

    DWORD64 firstEntry = 0;
    if (!ReadPointer(hProcess_, entityList, firstEntry)) {
        return MakeResult("EntityList", false, entityList,
                          "entity list head is not walkable (load into a match first)");
    }

    return MakeResult("EntityList", true, entityList, "");
}

// ----------------------------------------------------------------------------
// moduleBase + LOCAL_PLAYER (0x01E7D4B8) must resolve to a live player object.
// ----------------------------------------------------------------------------
ValidationResult OffsetValidator::ValidateLocalPlayerAccess() {
    const DWORD64 slot = moduleBase_ + ApexOffsets::LOCAL_PLAYER;

    DWORD64 localPlayer = 0;
    if (!ReadPointer(hProcess_, slot, localPlayer)) {
        return MakeResult("LocalPlayer", false, 0,
                          "no readable pointer at moduleBase+" +
                          HexText(ApexOffsets::LOCAL_PLAYER));
    }
    if (!LooksLikeUserPointer(localPlayer)) {
        return MakeResult("LocalPlayer", false, localPlayer,
                          "value is not a plausible user-space pointer");
    }
    if (!IsReadable(hProcess_, localPlayer, sizeof(DWORD64))) {
        return MakeResult("LocalPlayer", false, localPlayer,
                          "local player object is not readable");
    }

    return MakeResult("LocalPlayer", true, localPlayer, "");
}

// ----------------------------------------------------------------------------
// moduleBase + VIEW_MATRIX (0x022EE01) must yield 16 sane floats.
//
// CAVEAT: the documented value is the RVA of VTP_GetEngineTraceClient, i.e.
// *code*, not a matrix.  This check doubles as the canary for "the view matrix
// offset must be re-RE'd after a patch": non-finite / all-zero values or a
// zero w-row are flagged instead of silently producing garbage ESP boxes.
// ----------------------------------------------------------------------------
ValidationResult OffsetValidator::ValidateViewMatrixRead() {
    const DWORD64 address = moduleBase_ + ApexOffsets::VIEW_MATRIX;

    float matrix[16] = { 0.0f };
    if (!ReadBytes(hProcess_, address, matrix, sizeof(matrix))) {
        return MakeResult("ViewMatrix", false, 0,
                          "unreadable 64 bytes at moduleBase+" +
                          HexText(ApexOffsets::VIEW_MATRIX));
    }

    int  finiteCount = 0;
    bool anyNonZero  = false;
    for (int i = 0; i < 16; ++i) {
        if (std::isfinite(matrix[i])) ++finiteCount;
        if (matrix[i] != 0.0f) anyNonZero = true;
    }

    if (finiteCount < 16) {
        return MakeResult("ViewMatrix", false, address, "matrix contains non-finite values");
    }
    if (!anyNonZero) {
        return MakeResult("ViewMatrix", false, address,
                          "matrix is all zero (wrong offset, or not in a match)");
    }
    if (std::fabs(matrix[15]) < 1e-6f) {
        return MakeResult("ViewMatrix", false, address,
                          "w-row is zero: moduleBase+0x022EE01 looks like code "
                          "(VTP_GetEngineTraceClient) - offset needs re-RE");
    }

    return MakeResult("ViewMatrix", true, address, "");
}

// ----------------------------------------------------------------------------
// R5AC monitors a fixed set of r5apex VMT slots.  Conservative integrity
// check: every monitored RVA must (a) live inside .text and (b) stay readable.
// Unreadable => section layout changed (patch) or the page was re-protected by
// the anti-cheat; either way the hook set must be re-validated.
// ----------------------------------------------------------------------------
ValidationResult OffsetValidator::ValidateR5ACVMTIntegrity() {
    struct VmtTarget {
        const char* name;
        DWORD       rva;
    };

    static const VmtTarget targets[] = {
        { "VTP_GetEngineTraceClient", ApexOffsets::R5AC_VMT::GET_ENGINE_TRACE_CLIENT  },
        { "GetFileSystemInterface",   ApexOffsets::R5AC_VMT::GET_FILESYSTEM_INTERFACE },
        { "C_Player_Spawn",           ApexOffsets::R5AC_VMT::C_PLAYER_SPAWN            },
        { "GetEntityList",            ApexOffsets::R5AC_VMT::GET_ENTITY_LIST           },
        { "GetViewRenderInstance",    ApexOffsets::R5AC_VMT::GET_VIEW_RENDER_INSTANCE  },
    };

    const int total = static_cast<int>(sizeof(targets) / sizeof(targets[0]));
    int passed = 0;
    std::string failures;

    for (int i = 0; i < total; ++i) {
        const DWORD64 address = moduleBase_ + targets[i].rva;

        const bool insideText = (targets[i].rva >= ApexOffsets::Whitelist::R5APEX_MIN &&
                                 targets[i].rva <= ApexOffsets::Whitelist::R5APEX_MAX);
        const bool readable   = IsReadable(hProcess_, address, sizeof(DWORD64));

        if (insideText && readable) {
            ++passed;
        } else {
            if (!failures.empty()) failures += "; ";
            failures += targets[i].name;
            failures += insideText ? " (unreadable)" : " (outside .text)";
        }
    }

    return MakeResult("R5AC_VMT", passed == total, static_cast<DWORD64>(passed),
                      failures.empty() ? std::string("all monitored slots intact")
                                       : failures);
}


