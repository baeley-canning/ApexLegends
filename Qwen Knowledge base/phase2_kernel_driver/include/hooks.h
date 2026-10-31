/**
 * Phase 2 Kernel Driver - Hooks Header
 * 
 * Hook interfaces for process, memory, and Griffin VM hooking
 */

#pragma once

#ifndef __PHASE2_HOOKS_H__
#define __PHASE2_HOOKS_H__

#include "common.h"
#include "obfuscation.h"

// ============================================================================
// HOOK TYPES
// ============================================================================

typedef enum _HOOK_TYPE {
    HOOK_TYPE_PROCESS,
    HOOK_TYPE_MEMORY,
    HOOK_TYPE_GRIFFIN_VM,
    HOOK_TYPE_TELEMETRY,
    HOOK_TYPE_HANDLE,
    HOOK_TYPE_MAX
} HOOK_TYPE;

// Hook state enumeration
typedef enum _HOOK_STATE {
    HOOK_STATE_UNINITIALIZED = 0,
    HOOK_STATE_REGISTERED,
    HOOK_STATE_ACTIVE,
    HOOK_STATE_SUSPENDED,
    HOOK_STATE_RESTORED,
    HOOK_STATE_MAX
} HOOK_STATE, *PHOOK_STATE;

// ============================================================================
// PROCESS HOOK STRUCTURES
// ============================================================================

typedef struct _PROCESS_CREATE_INFO {
    HANDLE ProcessId;
    HANDLE ParentProcessId;
    LPWSTR ImageFileName;
    ULONG CreationFlags;
    LARGE_INTEGER CreateTime;
    LARGE_INTEGER UserTime;
    LARGE_INTEGER KernelTime;
} PROCESS_CREATE_INFO, *PPROCESS_CREATE_INFO;

typedef struct _PROCESS_EXIT_INFO {
    HANDLE ProcessId;
    NTSTATUS ExitStatus;
    LARGE_INTEGER ExitTime;
    ULONG_PTR ActiveThreads;
} PROCESS_EXIT_INFO, *PPROCESS_EXIT_INFO;

// Process hook callback types
typedef NTSTATUS(*PFN_PROCESS_CREATE_CALLBACK)(
    PPROCESS_CREATE_INFO pCreateInfo,
    PVOID pContext
);

typedef NTSTATUS(*PFN_PROCESS_EXIT_CALLBACK)(
    PPROCESS_EXIT_INFO pExitInfo,
    PVOID pContext
);

// ============================================================================
// MEMORY HOOK STRUCTURES
// ============================================================================

typedef struct _MEMORY_ACCESS_INFO {
    PVOID Address;
    SIZE_T Size;
    ACCESS_MASK AccessMask;
    ULONG Protection;
    BOOLEAN IsWrite;
    BOOLEAN IsExecute;
    BOOLEAN IsRead;
} MEMORY_ACCESS_INFO, *PMEMORY_ACCESS_INFO;

typedef struct _MEMORY_PROTECTION_INFO {
    PVOID BaseAddress;
    SIZE_T RegionSize;
    ULONG AllocationType;
    ULONG Protect;
} MEMORY_PROTECTION_INFO, *PMEMORY_PROTECTION_INFO;

// Memory hook callback types
typedef NTSTATUS(*PFN_MEMORY_READ_CALLBACK)(
    PMEMORY_ACCESS_INFO pAccessInfo,
    PVOID pBuffer,
    PVOID pContext
);

typedef NTSTATUS(*PFN_MEMORY_WRITE_CALLBACK)(
    PMEMORY_ACCESS_INFO pAccessInfo,
    PVOID pBuffer,
    PVOID pContext
);

typedef NTSTATUS(*PFN_MEMORY_PROTECT_CALLBACK)(
    PMEMORY_PROTECTION_INFO pProtectInfo,
    PVOID pContext
);

// ============================================================================
// GRIFIN VM HOOK STRUCTURES
// ============================================================================

// Griffin VM context structure
typedef struct _GRIFIN_VM_CONTEXT {
    ULONG64 VirtualRegisters[16];
    ULONG64 VirtualPC;
    ULONG64 VirtualSP;
    ULONG64 VirtualFlags;
    BOOLEAN IsVirtualized;
    BOOLEAN MBAEnabled;
    ULONG VMState;
} GRIFIN_VM_CONTEXT, *PGRIFIN_VM_CONTEXT;

// MBA folding configuration
typedef struct _MBA_FOLDING_CONFIG {
    BOOLEAN Enabled;
    ULONG MaxExpressions;
    ULONG ExpressionComplexity;
    ULONG FoldingThreshold;
    ULONG64 Seed;
} MBA_FOLDING_CONFIG, *PMBA_FOLDING_CONFIG;

// INT3 breakpoint resolution configuration
typedef struct _INT3_RESOLUTION_CONFIG {
    BOOLEAN Enabled;
    ULONG ResolutionStrategy;  // 0=linear, 1=polynomial, 2=exponential
    ULONG MaxResolutionAttempts;
    ULONG TimeoutMs;
} INT3_RESOLUTION_CONFIG, *PINT3_RESOLUTION_CONFIG;

// ============================================================================
// TELEMETRY HOOK STRUCTURES
// ============================================================================

typedef struct _TELEMETRY_EVENT {
    ULONG EventType;           // Input, Memory, Process, Handle, Driver
    ULONG64 Timestamp;
    PVOID Data;
    SIZE_T DataSize;
    ULONG CategoryMask;        // Bitmask of detection categories
} TELEMETRY_EVENT, *PTELEMETRY_EVENT;

typedef struct _TELEMETRY_BATCH {
    TELEMETRY_EVENT Events[64];
    ULONG EventCount;
    ULONG64 BatchTimestamp;
    BOOLEAN Encrypted;
    BOOLEAN Obfuscated;
} TELEMETRY_BATCH, *PTELEMETRY_BATCH;

// ============================================================================
// HANDLE HOOK STRUCTURES
// ============================================================================

typedef struct _HANDLE_INFO {
    HANDLE Handle;
    HANDLE ProcessId;
    PVOID Object;
    ULONG TypeIndex;
    ULONG Attributes;
    ULONG GrantedAccess;
} HANDLE_INFO, *PHANDLE_INFO;

typedef struct _HANDLE_REFRESH_INFO {
    PHANDLE_INFO Handles;
    ULONG HandleCount;
    ULONG RefreshIntervalMs;
    BOOLEAN ClearDetectionTraces;
} HANDLE_REFRESH_INFO, *PHANDLE_REFRESH_INFO;

// ============================================================================
// HOOK REGISTRATION STRUCTURE
// ============================================================================

typedef struct _HOOK_REGISTRATION {
    HOOK_TYPE Type;
    PVOID HookFunction;
    PVOID OriginalFunction;
    PVOID Context;
    PFN_PROCESS_CREATE_CALLBACK ProcessCreateCallback;
    PFN_PROCESS_EXIT_CALLBACK ProcessExitCallback;
    PFN_MEMORY_READ_CALLBACK MemoryReadCallback;
    PFN_MEMORY_WRITE_CALLBACK MemoryWriteCallback;
    PFN_MEMORY_PROTECT_CALLBACK MemoryProtectCallback;
    HOOK_STATE State;
    ULONG Flags;
} HOOK_REGISTRATION, *PHOOK_REGISTRATION;

// ============================================================================
// HOOK MANAGER STRUCTURE
// ============================================================================

typedef struct _HOOK_MANAGER {
    HOOK_REGISTRATION Hooks[HOOK_TYPE_MAX];
    ULONG HookCount;
    KSPIN_LOCK Lock;
    BOOLEAN Initialized;
    BOOLEAN Enabled;
} HOOK_MANAGER, *PHOOK_MANAGER;

// ============================================================================
// FUNCTION PROTOTYPES
// ============================================================================

// Process hooks
NTSTATUS
Phase2RegisterProcessHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

VOID
Phase2UnregisterProcessHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

// Memory hooks
NTSTATUS
Phase2RegisterMemoryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

VOID
Phase2UnregisterMemoryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

// Griffin VM hooks
NTSTATUS
Phase2RegisterGriffinHooks(
    _Inout_ PHOOK_MANAGER pHookManager,
    _In_ PGRIFIN_VM_CONTEXT pVmContext,
    _In_ PMBA_FOLDING_CONFIG pMbaConfig,
    _In_ PINT3_RESOLUTION_CONFIG pInt3Config
);

VOID
Phase2UnregisterGriffinHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

// Telemetry hooks
NTSTATUS
Phase2RegisterTelemetryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

VOID
Phase2UnregisterTelemetryHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

// Handle hooks
NTSTATUS
Phase2RegisterHandleHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

VOID
Phase2UnregisterHandleHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

// Hook manager operations
NTSTATUS
Phase2InitializeHookManager(
    _Out_ PHOOK_MANAGER* ppHookManager
);

VOID
Phase2CleanupHookManager(
    _In_opt_ PHOOK_MANAGER pHookManager
);

VOID
Phase2EnableHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

VOID
Phase2DisableHooks(
    _Inout_ PHOOK_MANAGER pHookManager
);

// ============================================================================
// MACROS
// ============================================================================

#define HOOK_FLAG_VIRTUALIZED       BIT(0)
#define HOOK_FLAG_ENCRYPTED         BIT(1)
#define HOOK_FLAG_OBFUSCATED        BIT(2)
#define HOOK_FLAG_TIMING_MASKED     BIT(3)
#define HOOK_FLAG_BEHAVIORAL_SPOOF  BIT(4)

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __PHASE2_HOOKS_H__
