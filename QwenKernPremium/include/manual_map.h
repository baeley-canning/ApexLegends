#pragma once
#include <windows.h>
#include <string>

// ============================================================================
// manual_map — PHASE 1.2 rung A7 ("MANUAL")
//
// WHY THIS EXISTS
//   docs\INJECTION_MENU_AND_RISK_MATRIX.txt rates A7 manual map as the PRIMARY
//   usermode rung: the payload never enters the PEB module list, no LoadLibrary
//   of the payload happens, the loader lock is never taken, and there is no
//   LDR_DATA_TABLE_ENTRY for an AC to walk.  That is a different detection
//   surface from A1/A2/A3/A4, which all end in the loader.
//
// WHAT IT DOES (all from the launcher, no in-target shellcode beyond a 30-byte
// entry-point call stub)
//   1. read the payload file, validate PE32+ / DLL
//   2. VirtualAllocEx(SizeOfImage, RW) in the target
//   3. copy headers + sections into a local image buffer
//   4. apply base relocations for the real load address
//   5. resolve imports against the TARGET's module bases (dependency DLLs are
//      pre-loaded with LoadLibraryA in the target when absent - they are
//      modules the game loads itself, not our payload)
//   6. write the finished image in one WriteProcessMemory
//   7. VirtualProtectEx per section (RX / RW / R)
//   8. call AddressOfEntryPoint(base, DLL_PROCESS_ATTACH, nullptr) on a fresh
//      thread; a non-zero return is the "entry executed" verdict
//
// LIMITS (documented, not hidden)
//   * needs VirtualAllocEx(VirtualAlloc) + a PAGE_EXECUTE* page in the target;
//     under Javelin/AGC both are refused on r5apex_dx12.exe -> the rung reports
//     the exact win32 error instead of pretending to work (measurement X2/X3).
//   * dependencies are still LoadLibrary'd in the target, so a dependency the
//     game did not have (d3d11 in a DX12-only install) becomes visible.
//   * TLS callbacks are handled by the PE's own CRT startup (DllMainCRTStartup
//     runs them); a payload with no CRT startup must do its own TLS work.
//   * the image is never unmapped: there is no DllMain(DETACH) on unload.
// ============================================================================

namespace ManualMapper {

struct MapResult {
    bool        success       = false;
    ULONGLONG   imageBase     = 0;
    bool        entryExecuted = false;
    DWORD       threadId      = 0;
    std::string error;
};

// Maps `dllPath` into `pid`.  Prints one "[A7] ..." line per step so a failed
// rung leaves a readable trace in the ladder log.
MapResult Map(DWORD pid, const std::string& dllPath);

} // namespace ManualMapper
