/**
 * Phase 2 Kernel Driver - Handle Management Implementation
 *
 * Handle refresh, trace clearing, and long-lived handle detection evasion
 */

#include "phase2.h"

// ============================================================================
// HANDLE REFRESH CONFIGURATION
// ============================================================================

#define HANDLE_REFRESH_INTERVAL_MS    (60 * 1000)   // 60 seconds (matches Javelin poll interval)
#define MAX_TRACKED_HANDLES           256
#define HANDLE_CACHE_SIZE             512

// ============================================================================
// GLOBAL STATE
// ============================================================================

typedef struct _HANDLE_STATE {
    HANDLE Handles[MAX_TRACKED_HANDLES];
    ULONG HandleCount;
    ULONG RefreshIntervalMs;
    LARGE_INTEGER LastRefreshTime;
    BOOLEAN ClearDetectionTraces;
    KSPIN_LOCK Lock;
} HANDLE_STATE, *PHANDLE_STATE;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Initialize handle state
 */
NTSTATUS
Phase2InitializeHandleState(
    _Out_ PHANDLE_STATE* ppHandleState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHANDLE_STATE pState = Phase2AllocatePool(NonPagedPool, sizeof(HANDLE_STATE));
    if (!pState) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    
    // Initialize handle array
    RtlZeroMemory(pState->Handles, sizeof(pState->Handles));
    pState->HandleCount = 0;
    pState->RefreshIntervalMs = HANDLE_REFRESH_INTERVAL_MS;
    pState->LastRefreshTime.QuadPart = 0;
    pState->ClearDetectionTraces = TRUE;
    
    KeInitializeSpinLock(&pState->Lock);
    
    *ppHandleState = pState;
    
    PHASE2_TRACE("Handle state initialized");
    
    return Status;
}

/**
 * @brief Cleanup handle state
 */
VOID
Phase2CleanupHandleState(
    _In_opt_ PHANDLE_STATE pState
)
{
    if (pState) {
        Phase2FreePool(pState);
    }
}

/**
 * @brief Refresh process handles to avoid long-lived handle detection
 */
NTSTATUS
Phase2RefreshHandlesInternal(
    _Inout_ PHANDLE_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    KeAcquireSpinLock(&pState->Lock, &pState->EventLockIrql);
    
    PHASE2_TRACE("Refreshing %d handles", pState->HandleCount);
    
    // Close and reopen each handle (pattern from PyGG research)
    for (ULONG i = 0; i < pState->HandleCount; i++) {
        HANDLE hHandle = pState->Handles[i];
        
        if (hHandle) {
            // Close current handle
            CloseHandle(hHandle);
            
            // Reopen with fresh handle
            // (In production, this would use appropriate OpenProcess/OpenFile/etc.)
            hHandle = NULL;  // Placeholder - actual implementation would reopen
            
            pState->Handles[i] = hHandle;
        }
    }
    
    // Update last refresh time
    pState->LastRefreshTime = KeQueryPerformanceCounter(NULL);
    
    // Clear detection traces if enabled
    if (pState->ClearDetectionTraces) {
        Phase2ClearAllDetectionTraces();
    }
    
    KeReleaseSpinLock(&pState->Lock, pState->EventLockIrql);
    
    PHASE2_TRACE("Handle refresh completed");
    
    return Status;
}

/**
 * @brief Add handle to tracked list
 */
NTSTATUS
Phase2TrackHandle(
    _Inout_ PHANDLE_STATE pState,
    _In_ HANDLE hHandle
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    KeAcquireSpinLock(&pState->Lock, &pState->EventLockIrql);
    
    if (pState->HandleCount < MAX_TRACKED_HANDLES) {
        pState->Handles[pState->HandleCount++] = hHandle;
    }
    
    KeReleaseSpinLock(&pState->Lock, pState->EventLockIrql);
    
    return Status;
}

/**
 * @brief Check if handle refresh is needed based on interval
 */
BOOLEAN
Phase2IsHandleRefreshNeeded(
    _In_ PHANDLE_STATE pState
)
{
    LARGE_INTEGER currentTime = KeQueryPerformanceCounter(NULL);
    LONGLONG elapsedMs = (currentTime.QuadPart - pState->LastRefreshTime.QuadPart) / 
                         (ONE_SECOND / 1000);
    
    return elapsedMs >= pState->RefreshIntervalMs;
}

// ============================================================================
// TRACE CLEARING FUNCTIONS
// ============================================================================

/**
 * @brief Clear all detection traces for handle refresh
 */
NTSTATUS
Phase2ClearAllDetectionTraces(
    VOID
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Clearing all detection traces");
    
    // Clear PiDDBCacheTable
    Status = Phase2ClearPiDDBCacheTable();
    if (!NT_SUCCESS(Status)) {
        PHASE2_ERROR("Failed to clear PiDDBCacheTable: %d", Status);
    }
    
    // Clear MmUnloadedDrivers
    Status = Phase2ClearMmUnloadedDrivers();
    if (!NT_SUCCESS(Status)) {
        PHASE2_ERROR("Failed to clear MmUnloadedDrivers: %d", Status);
    }
    
    // Clear g_KernelHashBucketList
    Status = Phase2ClearKernelHashBucketList();
    if (!NT_SUCCESS(Status)) {
        PHASE2_ERROR("Failed to clear g_KernelHashBucketList: %d", Status);
    }
    
    PHASE2_TRACE("All detection traces cleared");
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
