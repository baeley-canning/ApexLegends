#pragma once
#include <windows.h>
#include <string>
#include <vector>

// ============================================================================
// OffsetValidator — Validates memory read capabilities against live game 
// structures. Uses injected process context to confirm memory access integrity
// before rendering begins. Addresses the core problem: r5apex.exe offsets drift
// with each patch and hardcoded values become stale.
// ============================================================================

struct ValidationResult {
    std::string name;
    bool valid;
    DWORD64 actualValue;
    std::string errorMessage;
};

class OffsetValidator {
public:
    OffsetValidator();
    ~OffsetValidator() = default;

    // Initialize with target process handle and r5apex.exe base address
    bool Initialize(HANDLE hProcess, DWORD64 moduleBase);

    // Validate all known offsets — returns list of pass/fail results
    std::vector<ValidationResult> ValidateAll();

    // Individual validation checks
    ValidationResult ValidateEntityListPointer();
    ValidationResult ValidateViewMatrixRead();
    ValidationResult ValidateLocalPlayerAccess();
    ValidationResult ValidateR5ACVMTIntegrity();

private:
    HANDLE hProcess_;
    DWORD64 moduleBase_;
};
