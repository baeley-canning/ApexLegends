/**
 * Phase 2 Kernel Driver - Main Header
 * 
 * Main driver entry point and coordination for Javelin evasion patterns
 */

#pragma once

#ifndef __PHASE2_H__
#define __PHASE2_H__

#include "common.h"
#include "hooks.h"
#include "obfuscation.h"
#include "griffin.h"

// ============================================================================
// DRIVER ENTRY POINTS
// ============================================================================

// Driver entry point
DRIVER_INITIALIZE DriverEntry;

// Driver unload routine
DRIVER_UNLOAD DriverUnload;

// ============================================================================
// DRIVER CONTEXT STRUCTURE
// ============================================================================

typedef struct _PHASE2_CONTEXT {
    // Core components
    HOOK_MANAGER HookManager;
    OBFUSCATION_ENGINE ObfuscationEngine;
    GRIFIN_VM_CONTEXT GriffinContext;
    GRIFIN_OBFUSCATION_CONFIG GriffinConfig;
    
    // Configuration
    ULONG DetectionCategories;
    BOOLEAN EnableXorEncryption;
    BOOLEAN EnableTimingEvasion;
    BOOLEAN EnableGriffinVM;
    BOOLEAN EnableTelemetryObfuscation;
    
    // Statistics
    ULONGLONG TotalInstructionsExecuted;
    ULONGLONG TotalBytesEncrypted;
    ULONGLONG TotalHandleRefreshes;
    LARGE_INTEGER InitializationTime;
    
    // Runtime state
    BOOLEAN DriverActive;
    BOOLEAN EvasionEnabled;
    KSPIN_LOCK ContextLock;
} PHASE2_CONTEXT, *PPHASE2_CONTEXT;

// ============================================================================
// EXTERNAL REFERENCES
// ============================================================================

extern PHASE2_CONTEXT g_Phase2Context;

// ============================================================================
// FUNCTION PROTOTYPES - INITIALIZATION
// ============================================================================

NTSTATUS
Phase2InitializeDriver(
    _In_ PDRIVER_OBJECT pDriverObject,
    _In_ PUNICODE_STRING pRegistryPath
);

VOID
Phase2CleanupDriver(
    VOID
);

// ============================================================================
// FUNCTION PROTOTYPES - DETECTION CATEGORY MANAGEMENT
// ============================================================================

VOID
Phase2EnableDetectionCategory(
    _In_ ULONG CategoryMask
);

VOID
Phase2DisableDetectionCategory(
    _In_ ULONG CategoryMask
);

BOOLEAN
Phase2IsDetectionCategoryEnabled(
    _In_ ULONG CategoryMask
);

ULONG
Phase2GetAllDetectionCategories(
    VOID
);

// ============================================================================
// FUNCTION PROTOTYPES - EVASION CONTROL
// ============================================================================

VOID
Phase2EnableEvasion(
    VOID
);

VOID
Phase2DisableEvasion(
    VOID
);

BOOLEAN
Phase2IsEvasionEnabled(
    VOID
);

// ============================================================================
// FUNCTION PROTOTYPES - TELEMETRY
// ============================================================================

NTSTATUS
Phase2CollectTelemetryEvent(
    _In_ ULONG EventType,
    _In_reads_bytes_opt_(DataSize) PVOID pData,
    _In_ SIZE_T DataSize
);

NTSTATUS
Phase2FlushTelemetryBatch(
    _In_ BOOLEAN ForceTransmission
);

// ============================================================================
// FUNCTION PROTOTYPES - GRIFIN VM CONTROL
// ============================================================================

NTSTATUS
Phase2InitializeGriffinVM(
    VOID
);

VOID
Phase2CleanupGriffinVM(
    VOID
);

NTSTATUS
Phase2EnterGriffinVirtualization(
    VOID
);

NTSTATUS
Phase2ExitGriffinVirtualization(
    VOID
);

// ============================================================================
// FUNCTION PROTOTYPES - KDMAPPER COMPATIBILITY
// ============================================================================

NTSTATUS
Phase2PrepareForKDMapperInjection(
    VOID
);

NTSTATUS
Phase2NotifyKDMapperOfDriverState(
    VOID
);

// ============================================================================
// MACROS
// ============================================================================

#define PHASE2_CONTEXT_LOCK_ACQUIRE()   KeAcquireSpinLock(&g_Phase2Context.ContextLock, &g_Phase2Context.ContextLockIrql)
#define PHASE2_CONTEXT_LOCK_RELEASE()   KeReleaseSpinLock(&g_Phase2Context.ContextLock, g_Phase2Context.ContextLockIrql)

#define PHASE2_IS_CATEGORY_ENABLED(cat) (g_Phase2Context.DetectionCategories & (cat))

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __PHASE2_H__
