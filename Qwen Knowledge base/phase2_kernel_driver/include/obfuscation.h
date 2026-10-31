/**
 * Phase 2 Kernel Driver - Obfuscation Header
 * 
 * XOR encryption, timing evasion, handle refresh, and MBA folding for Javelin evasion
 */

#pragma once

#ifndef __PHASE2_OBFUSCATION_H__
#define __PHASE2_OBFUSCATION_H__

#include "common.h"

// ============================================================================
// XOR ENCRYPTION CONFIGURATION
// ============================================================================

typedef struct _XOR_KEY {
    UCHAR Key[XOR_BLOCK_SIZE];
    ULONG64 RotationCounter;
    LARGE_INTEGER LastRotationTime;
} XOR_KEY, *PXOR_KEY;

typedef struct _XOR_CONTEXT {
    XOR_KEY CurrentKey;
    XOR_KEY PreviousKey;
    BOOLEAN KeyRotated;
    ULONG EncryptedBytes;
    ULONG DecryptedBytes;
} XOR_CONTEXT, *PXOR_CONTEXT;

// ============================================================================
// TIMING EVASION CONFIGURATION
// ============================================================================

// Human baseline reaction time distribution: N(250ms, σ=75ms)
typedef struct _REACTION_TIME_CONFIG {
    ULONG MeanMs;           // 250ms default
    ULONG StdDevMs;         // 75ms default
    ULONG MinMs;            // 180ms baseline
    ULONG MaxMs;            // 400ms baseline
} REACTION_TIME_CONFIG, *PREACTION_TIME_CONFIG;

// Micro-jitter configuration: N(0, σ=1.5°) at 60Hz
typedef struct _MICRO_JITTER_CONFIG {
    DOUBLE StdDevDeg;       // 1.5 degrees default
    ULONG FrequencyHz;      // 60Hz default
    DOUBLE TremorFreqHz;    // 8Hz tremor component
    DOUBLE MaxDriftDeg;     // Maximum drift from baseline
} MICRO_JITTER_CONFIG, *PMICRO_JITTER_CONFIG;

// Kill-streak decay configuration: exponential with τ ≈ 8-12 kills
typedef struct _KILL_STREAK_DECAY_CONFIG {
    DOUBLE Tau;             // Decay constant (8-12 kills)
    DOUBLE BaseAccuracy;    // 0.85-0.90 default
    ULONG FatigueStartKills;// 20+ kills for fatigue penalty
    DOUBLE FatiguePenalty;  // +5-10% after fatigue threshold
} KILL_STREAK_DECAY_CONFIG, *PKILL_STREAK_DECAY_CONFIG;

// ============================================================================
// HANDLE REFRESH CONFIGURATION
// ============================================================================

typedef struct _HANDLE_REFRESH_CONFIG {
    ULONG RefreshIntervalMs;        // Default: 60s (matches Javelin poll interval)
    BOOLEAN ClearPiDDBCacheTable;   // Clear PiDDBCacheTable on refresh
    BOOLEAN ClearMmUnloadedDrivers; // Clear MmUnloadedDrivers on refresh
    BOOLEAN ClearKernelHashList;    // Clear g_KernelHashBucketList on refresh
    ULONG MaxHandleCount;           // Maximum handles to track
} HANDLE_REFRESH_CONFIG, *PHANDLE_REFRESH_CONFIG;

// ============================================================================
// MEMORY PROTECTION CONFIGURATION
// ============================================================================

typedef struct _MEMORY_PROTECTION_CONFIG {
    BOOLEAN EnableMBAFolding;
    BOOLEAN EnableVirtualization;
    ULONG ProtectionFlags;
    ULONG MBAExpressionCount;
    ULONG MBATreeDepth;
} MEMORY_PROTECTION_CONFIG, *PMEMORY_PROTECTION_CONFIG;

// ============================================================================
// MODULE OBFUSCATION CONFIGURATION
// ============================================================================

typedef struct _MODULE_OBFUSCATION_CONFIG {
    BOOLEAN ObfuscateModuleNames;
    BOOLEAN ObfuscateSectionNames;
    BOOLEAN ObfuscateExportTables;
    BOOLEAN ObfuscateImportTables;
    BOOLEAN ObfuscateRelocations;
} MODULE_OBFUSCATION_CONFIG, *PMODULE_OBFUSCATION_CONFIG;

// ============================================================================
// GRIFIN VM OBFUSCATION CONFIGURATION
// ============================================================================

typedef struct _GRIFIN_OBFUSCATION_CONFIG {
    BOOLEAN EnableGriffinSections;
    BOOLEAN EnableMBAFolding;
    BOOLEAN EnableINT3Resolution;
    ULONG MBAComplexity;
    ULONG INT3Strategy;
    ULONG TimeoutMs;
} GRIFIN_OBFUSCATION_CONFIG, *PGRIFIN_OBFUSCATION_CONFIG;

// ============================================================================
// OBFUSCATION ENGINE STRUCTURE
// ============================================================================

typedef struct _OBFUSCATION_ENGINE {
    XOR_CONTEXT XorContext;
    REACTION_TIME_CONFIG ReactionTimeConfig;
    MICRO_JITTER_CONFIG JitterConfig;
    KILL_STREAK_DECAY_CONFIG DecayConfig;
    HANDLE_REFRESH_CONFIG HandleRefreshConfig;
    MEMORY_PROTECTION_CONFIG MemoryProtectionConfig;
    MODULE_OBFUSCATION_CONFIG ModuleConfig;
    GRIFIN_OBFUSCATION_CONFIG GriffinConfig;
    BOOLEAN Initialized;
    KSPIN_LOCK Lock;
} OBFUSCATION_ENGINE, *POBFUSCATION_ENGINE;

// ============================================================================
// FUNCTION PROTOTYPES - XOR ENCRYPTION
// ============================================================================

NTSTATUS
Phase2XorInitialize(
    _Inout_ PXOR_CONTEXT pContext,
    _In_opt_ PUCHAR pSeedKey,
    _In_opt_ ULONG SeedKeyLen
);

VOID
Phase2XorEncrypt(
    _Inout_ PXOR_CONTEXT pContext,
    _In_reads_bytes_(Length) PUCHAR pData,
    _In_ SIZE_T Length
);

VOID
Phase2XorDecrypt(
    _Inout_ PXOR_CONTEXT pContext,
    _In_reads_bytes_(Length) PUCHAR pData,
    _In_ SIZE_T Length
);

NTSTATUS
Phase2XorRotateKey(
    _Inout_ PXOR_CONTEXT pContext
);

// ============================================================================
// FUNCTION PROTOTYPES - TIMING EVASION
// ============================================================================

ULONG
Phase2GetReactionTimeMs(
    _In_ PREACTION_TIME_CONFIG pConfig
);

DOUBLE
Phase2GetMicroJitterDeg(
    _In_ PMICRO_JITTER_CONFIG pConfig,
    _In_ ULONG64 FrameIndex
);

DOUBLE
Phase2GetKillStreakDecay(
    _In_ PKILL_STREAK_DECAY_CONFIG pConfig,
    _In_ ULONG KillCount
);

LARGE_INTEGER
Phase2GetBatchInterval(
    _In_ ULONG MeanSeconds,
    _In_ ULONG StdDevSeconds
);

// ============================================================================
// FUNCTION PROTOTYPES - HANDLE REFRESH
// ============================================================================

NTSTATUS
Phase2RefreshHandles(
    _Inout_ PHANDLE_REFRESH_CONFIG pConfig
);

NTSTATUS
Phase2ClearDetectionTraces(
    _In_ PHANDLE_REFRESH_CONFIG pConfig
);

// ============================================================================
// FUNCTION PROTOTYPES - MEMORY OBFUSCATION
// ============================================================================

NTSTATUS
Phase2ApplyMBAFolding(
    _In_reads_bytes_(Size) PUCHAR pData,
    _In_ SIZE_T Size,
    _In_ PMEMORY_PROTECTION_CONFIG pConfig
);

NTSTATUS
Phase2VirtualizeMemoryRegion(
    _In_ PVOID BaseAddress,
    _In_ SIZE_T Size,
    _In_ PMEMORY_PROTECTION_CONFIG pConfig
);

// ============================================================================
// FUNCTION PROTOTYPES - MODULE OBFUSCATION
// ============================================================================

NTSTATUS
Phase2ObfuscateModuleName(
    _Inout_ PWSTR pModuleName,
    _In_ PMODULE_OBFUSCATION_CONFIG pConfig
);

NTSTATUS
Phase2ObfuscateSectionName(
    _Inout_ PCHAR pSectionName,
    _In_ PMODULE_OBFUSCATION_CONFIG pConfig
);

// ============================================================================
// FUNCTION PROTOTYPES - GRIFIN OBFUSCATION
// ============================================================================

NTSTATUS
Phase2ApplyGriffinMBA(
    _In_reads_bytes_(Size) PUCHAR pData,
    _In_ SIZE_T Size,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
);

NTSTATUS
Phase2ResolveINT3Breakpoints(
    _In_ PVOID pContext,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
);

// ============================================================================
// MACROS
// ============================================================================

#define OBFUSCATION_FLAG_ENCRYPTED      BIT(0)
#define OBFUSCATION_FLAG_TIME_MASKED    BIT(1)
#define OBFUSCATION_FLAG_BEHAVIORAL     BIT(2)
#define OBFUSCATION_FLAG_GRIFIN_VM      BIT(3)
#define OBFUSCATION_FLAG_MBA_FOLDED     BIT(4)

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __PHASE2_OBFUSCATION_H__
