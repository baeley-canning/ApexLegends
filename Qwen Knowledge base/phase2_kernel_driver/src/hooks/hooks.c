/**
 * Phase 2 Kernel Driver - Hooks Implementation
 *
 * Hook registration, enable/disable operations, and hook manager management
 */

#include "phase2.h"

// ============================================================================
// HOOK TYPE STRINGS
// ============================================================================

PCSTR HookTypeStrings[] = {
    "PROCESS",
    "MEMORY",
    "GRIFIN_VM",
    "TELEMETRY",
    "HANDLE"
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Initialize hook manager
 */
NTSTATUS
Phase2InitializeHookManager(
    _Out_ PHOOK_MANAGER* ppHookManager
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHOOK_MANAGER pManager = Phase2AllocatePool(NonPagedPool, sizeof(HOOK_MANAGER));
    if (!pManager) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    
    // Initialize hook manager state
    RtlZeroMemory(pManager->Hooks, sizeof(pManager->Hooks));
    pManager->HookCount = 0;
    pManager->Initialized = TRUE;
    pManager->Enabled = FALSE;
    
    KeInitializeSpinLock(&pManager->Lock);
    
    *ppHookManager = pManager;
    
    PHASE2_TRACE("Hook manager initialized");
    
    return Status;
}

/**
 * @brief Cleanup hook manager
 */
VOID
Phase2CleanupHookManager(
    _In_opt_ PHOOK_MANAGER pManager
)
{
    if (pManager) {
        // Disable all hooks before cleanup
        Phase2DisableHooks(pManager);
        
        // Cleanup each hook type
        for (ULONG i = 0; i < HOOK_TYPE_MAX; i++) {
            PHOOK_REGISTRATION pHook = &pManager->Hooks[i];
            
            if (pHook->State >= HOOK_STATE_REGISTERED) {
                // Free hook-specific resources if needed
                if (pHook->Context) {
                    Phase2FreePool(pHook->Context);
                    pHook->Context = NULL;
                }
                
                pHook->State = HOOK_STATE_RESTORED;
            }
        }
        
        Phase2FreePool(pManager);
    }
}

/**
 * @brief Enable all hooks
 */
VOID
Phase2EnableHooks(
    _Inout_ PHOOK_MANAGER pManager
)
{
    if (!pManager) {
        return;
    }
    
    KeAcquireSpinLock(&pManager->Lock, &pManager->EventLockIrql);
    
    PHASE2_TRACE("Enabling all hooks");
    
    for (ULONG i = 0; i < HOOK_TYPE_MAX; i++) {
        PHOOK_REGISTRATION pHook = &pManager->Hooks[i];
        
        if (pHook->State >= HOOK_STATE_REGISTERED) {
            pHook->State = HOOK_STATE_ACTIVE;
            
            // Call enable callback if available
            if (pHook->HookFunction) {
                PHASE2_TRACE("Enabled %s hook", HookTypeStrings[i]);
            }
        }
    }
    
    pManager->Enabled = TRUE;
    
    KeReleaseSpinLock(&pManager->Lock, pManager->EventLockIrql);
    
    PHASE2_TRACE("All hooks enabled");
}

/**
 * @brief Disable all hooks
 */
VOID
Phase2DisableHooks(
    _Inout_ PHOOK_MANAGER pManager
)
{
    if (!pManager) {
        return;
    }
    
    KeAcquireSpinLock(&pManager->Lock, &pManager->EventLockIrql);
    
    PHASE2_TRACE("Disabling all hooks");
    
    for (ULONG i = 0; i < HOOK_TYPE_MAX; i++) {
        PHOOK_REGISTRATION pHook = &pManager->Hooks[i];
        
        if (pHook->State >= HOOK_STATE_REGISTERED) {
            // Call disable callback if available
            if (pHook->HookFunction) {
                PHASE2_TRACE("Disabled %s hook", HookTypeStrings[i]);
            }
            
            pHook->State = HOOK_STATE_SUSPENDED;
        }
    }
    
    pManager->Enabled = FALSE;
    
    KeReleaseSpinLock(&pManager->Lock, pManager->EventLockIrql);
    
    PHASE2_TRACE("All hooks disabled");
}

// ============================================================================
// PROCESS HOOKS
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
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_PROCESS];
    
    // Set hook function pointers
    pHookReg->Type = HOOK_TYPE_PROCESS;
    pHookReg->State = HOOK_STATE_REGISTERED;
    pHookReg->Flags = HOOK_FLAG_BEHAVIORAL_SPOOF | HOOK_FLAG_TIMING_MASKED;
    
    // Initialize context if needed
    pHookReg->Context = Phase2AllocatePool(NonPagedPool, sizeof(HANDLE));
    if (pHookReg->Context) {
        *(PHANDLE)pHookReg->Context = NULL;
    }
    
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
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_PROCESS];
    
    // Update hook state
    pHookReg->State = HOOK_STATE_RESTORED;
    
    // Free context if allocated
    if (pHookReg->Context) {
        Phase2FreePool(pHookReg->Context);
        pHookReg->Context = NULL;
    }
    
    PHASE2_TRACE("Process hooks unregistered");
}

// ============================================================================
// MEMORY HOOKS
// ============================================================================

/**
 * @brief Register memory access hooks
 */
NTSTATUS
Phase2RegisterMemoryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pHookManager) {
        return STATUS_INVALID_PARAMETER;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_MEMORY];
    
    // Set hook function pointers
    pHookReg->Type = HOOK_TYPE_MEMORY;
    pHookReg->State = HOOK_STATE_REGISTERED;
    pHookReg->Flags = HOOK_FLAG_ENCRYPTED | HOOK_FLAG_OBFUSCATED | HOOK_FLAG_BEHAVIORAL_SPOOF;
    
    // Initialize context if needed
    pHookReg->Context = Phase2AllocatePool(NonPagedPool, sizeof(HANDLE));
    if (pHookReg->Context) {
        *(PHANDLE)pHookReg->Context = NULL;
    }
    
    pHookManager->HookCount++;
    
    PHASE2_TRACE("Memory hooks registered");
    
    return Status;
}

/**
 * @brief Unregister memory hooks
 */
VOID
Phase2UnregisterMemoryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    if (!pHookManager) {
        return;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_MEMORY];
    
    // Update hook state
    pHookReg->State = HOOK_STATE_RESTORED;
    
    // Free context if allocated
    if (pHookReg->Context) {
        Phase2FreePool(pHookReg->Context);
        pHookReg->Context = NULL;
    }
    
    PHASE2_TRACE("Memory hooks unregistered");
}

// ============================================================================
// GRIFIN VM HOOKS
// ============================================================================

/**
 * @brief Register Griffin VM hooks
 */
NTSTATUS
Phase2RegisterGriffinHooks(
    _Inout_ PHOOK_MANAGER pHookManager,
    _In_ PGRIFIN_VM_CONTEXT pVmContext,
    _In_opt_ PMBA_FOLDING_CONFIG pMbaConfig,
    _In_opt_ PINT3_RESOLUTION_CONFIG pInt3Config
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pHookManager) {
        return STATUS_INVALID_PARAMETER;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_GRIFFIN_VM];
    
    // Set hook function pointers
    pHookReg->Type = HOOK_TYPE_GRIFFIN_VM;
    pHookReg->State = HOOK_STATE_REGISTERED;
    pHookReg->Flags = HOOK_FLAG_VIRTUALIZED | HOOK_FLAG_ENCRYPTED |
                      HOOK_FLAG_OBFUSCATED | HOOK_FLAG_TIMING_MASKED;
    
    // Initialize context
    if (pVmContext) {
        pHookReg->Context = Phase2AllocatePool(NonPagedPool, sizeof(GRIFIN_VM_CONTEXT));
        if (pHookReg->Context) {
            RtlCopyMemory(pHookReg->Context, pVmContext, sizeof(GRIFIN_VM_CONTEXT));
        }
    }
    
    pHookManager->HookCount++;
    
    PHASE2_TRACE("Griffin VM hooks registered");
    
    return Status;
}

/**
 * @brief Unregister Griffin VM hooks
 */
VOID
Phase2UnregisterGriffinHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    if (!pHookManager) {
        return;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_GRIFFIN_VM];
    
    // Update hook state
    pHookReg->State = HOOK_STATE_RESTORED;
    
    // Free context if allocated
    if (pHookReg->Context) {
        Phase2FreePool(pHookReg->Context);
        pHookReg->Context = NULL;
    }
    
    PHASE2_TRACE("Griffin VM hooks unregistered");
}

// ============================================================================
// TELEMETRY HOOKS
// ============================================================================

/**
 * @brief Register telemetry hooks
 */
NTSTATUS
Phase2RegisterTelemetryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pHookManager) {
        return STATUS_INVALID_PARAMETER;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_TELEMETRY];
    
    // Set hook function pointers
    pHookReg->Type = HOOK_TYPE_TELEMETRY;
    pHookReg->State = HOOK_STATE_REGISTERED;
    pHookReg->Flags = HOOK_FLAG_ENCRYPTED | HOOK_FLAG_TIME_MASKED;
    
    // Initialize context if needed
    pHookReg->Context = Phase2AllocatePool(NonPagedPool, sizeof(HANDLE));
    if (pHookReg->Context) {
        *(PHANDLE)pHookReg->Context = NULL;
    }
    
    pHookManager->HookCount++;
    
    PHASE2_TRACE("Telemetry hooks registered");
    
    return Status;
}

/**
 * @brief Unregister telemetry hooks
 */
VOID
Phase2UnregisterTelemetryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    if (!pHookManager) {
        return;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_TELEMETRY];
    
    // Update hook state
    pHookReg->State = HOOK_STATE_RESTORED;
    
    // Free context if allocated
    if (pHookReg->Context) {
        Phase2FreePool(pHookReg->Context);
        pHookReg->Context = NULL;
    }
    
    PHASE2_TRACE("Telemetry hooks unregistered");
}

// ============================================================================
// HANDLE HOOKS
// ============================================================================

/**
 * @brief Register handle hooks
 */
NTSTATUS
Phase2RegisterHandleHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pHookManager) {
        return STATUS_INVALID_PARAMETER;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_HANDLE];
    
    // Set hook function pointers
    pHookReg->Type = HOOK_TYPE_HANDLE;
    pHookReg->State = HOOK_STATE_REGISTERED;
    pHookReg->Flags = HOOK_FLAG_BEHAVIORAL_SPOOF | HOOK_FLAG_TIMING_MASKED;
    
    // Initialize context if needed
    pHookReg->Context = Phase2AllocatePool(NonPagedPool, sizeof(HANDLE));
    if (pHookReg->Context) {
        *(PHANDLE)pHookReg->Context = NULL;
    }
    
    pHookManager->HookCount++;
    
    PHASE2_TRACE("Handle hooks registered");
    
    return Status;
}

/**
 * @brief Unregister handle hooks
 */
VOID
Phase2UnregisterHandleHooks(
    _Inout_ PHOOK_MANAGER pHookManager
)
{
    if (!pHookManager) {
        return;
    }
    
    PHOOK_REGISTRATION pHookReg = &pHookManager->Hooks[HOOK_TYPE_HANDLE];
    
    // Update hook state
    pHookReg->State = HOOK_STATE_RESTORED;
    
    // Free context if allocated
    if (pHookReg->Context) {
        Phase2FreePool(pHookReg->Context);
        pHookReg->Context = NULL;
    }
    
    PHASE2_TRACE("Handle hooks unregistered");
}

// ============================================================================
// END OF FILE
// ============================================================================
