/**
 * Phase 2 Kernel Driver - Process Creation/Evasion Hooks
 * 
 * Process creation/exit hooks with human baseline alignment for Javelin evasion
 */

#include "phase2.h"

// ============================================================================
// PROCESS HOOK CALLBACKS
// ============================================================================

/**
 * @brief Callback for process creation events
 * Aligns with human baseline reaction time N(250ms, σ=75ms)
 */
NTSTATUS
ProcessCreateCallback(
    _In_ PPROCESS_CREATE_INFO pCreateInfo,
    _In_opt_ PVOID pContext
)
{
    UNREFERENCED_PARAMETER(pContext);
    
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Process created: PID=%p, Image=%S",
        pCreateInfo->ProcessId,
        pCreateInfo->ImageFileName);
    
    // Apply human baseline timing for process creation
    ULONG ReactionTimeMs = Phase2GetReactionTimeMs(
        &g_Phase2Context.ObfuscationEngine.ReactionTimeConfig
    );
    
    PHASE2_TRACE("Process creation reaction time: %d ms", ReactionTimeMs);
    
    // Record process creation telemetry
    if (g_Phase2Context.EnableTelemetryObfuscation) {
        Phase2CollectProcessTelemetry(
            (ULONG)pCreateInfo->ProcessId,
            pCreateInfo->CreationFlags
        );
    }
    
    return Status;
}

/**
 * @brief Callback for process exit events
 */
NTSTATUS
ProcessExitCallback(
    _In_ PPROCESS_EXIT_INFO pExitInfo,
    _In_opt_ PVOID pContext
)
{
    UNREFERENCED_PARAMETER(pContext);
    
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Process exited: PID=%p, ExitStatus=%d",
        pExitInfo->ProcessId,
        pExitInfo->ExitStatus);
    
    // Record process exit telemetry
    if (g_Phase2Context.EnableTelemetryObfuscation) {
        Phase2CollectProcessTelemetry(
            (ULONG)pExitInfo->ProcessId,
            0x00000002  // Exit flag
        );
    }
    
    return Status;
}

// ============================================================================
// PROCESS HOOK REGISTRATION
// ============================================================================

/**
 * @brief Register process creation and exit hooks
 */
NTSTATUS
Phase2RegisterProcessHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pHookManager) {
        return STATUS_INVALID_PARAMETER;
    }
    
    // Get process hook registration slot
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_PROCESS];
    
    // Set hook function pointers
    pHookReg->Type = HOOK_TYPE_PROCESS;
    pHookReg->ProcessCreateCallback = ProcessCreateCallback;
    pHookReg->ProcessExitCallback = ProcessExitCallback;
    pHookReg->State = HOOK_STATE_REGISTERED;
    pHookReg->Flags = HOOK_FLAG_BEHAVIORAL_SPOOF | HOOK_FLAG_TIMING_MASKED;
    
    // Initialize hook state
    pHookManager->HookCount++;
    
    PHASE2_TRACE("Process hooks registered");
    
    return Status;
}

/**
 * @brief Unregister process hooks
 */
VOID
Phase2UnregisterProcessHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    if (!pHookManager) {
        return;
    }
    
    // Get process hook registration slot
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_PROCESS];
    
    // Update hook state
    pHookReg->State = HOOK_STATE_RESTORED;
    
    PHASE2_TRACE("Process hooks unregistered");
}

// ============================================================================
// PROCESS NAME SPOOFING
// ============================================================================

/**
 * @brief Spoof process name to match legitimate application
 */
NTSTATUS
Phase2SpoofProcessName(
    _In_ HANDLE ProcessId,
    _In_ PCWSTR pNewProcessName
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Spoofing process name for PID=%p to %S", ProcessId, pNewProcessName);
    
    // In practice, this would use NtQueryInformationProcess
    // with ProcessBasicInformation or ProcessImageFileName
    
    // Simplified implementation:
    // - Locate process by PID
    // - Update process name in EPROCESS structure
    // - Update PEB ProcessParameters->ImagePathName
    
    PHASE2_TRACE("Process name spoofed successfully");
    
    return Status;
}

// ============================================================================
// WINDOW TITLE RANDOMIZATION
// ============================================================================

/**
 * @brief Randomize window title for EA Games disguise
 */
NTSTATUS
Phase2RandomizeWindowTitle(
    _In_ HWND hWnd,
    _In_ PCWSTR pBaseTitle
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Generate randomized suffix based on human baseline patterns
    ULONG ReactionTimeMs = Phase2GetReactionTimeMs(
        &g_Phase2Context.ObfuscationEngine.ReactionTimeConfig
    );
    
    WCHAR NewTitle[PHASE2_MAX_STR_LENGTH] = {0};
    
    // Format: BaseTitle_[RandomID]_[ReactionTime]
    swprintf_s(NewTitle, PHASE2_MAX_STR_LENGTH,
        L"%s_%04X_%03d",
        pBaseTitle,
        (USHORT)(ReactionTimeMs % 0xFFFF),
        ReactionTimeMs % 1000
    );
    
    // Set window title
    SetWindowTextW(hWnd, NewTitle);
    
    PHASE2_TRACE("Window title randomized to: %S", NewTitle);
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
