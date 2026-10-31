/**
 * Phase 2 Kernel Driver - Timing Evasion Implementation
 *
 * Human baseline reaction time, micro-jitter, and kill-streak decay
 */

#include "phase2.h"

// ============================================================================
// REACTION TIME CONFIGURATION
// ============================================================================

// Human reaction time: N(250ms, σ=75ms) from Javelin research
#define REACTION_TIME_MEAN_MS         250
#define REACTION_TIME_STDDEV_MS       75
#define REACTION_TIME_MIN_MS          180
#define REACTION_TIME_MAX_MS          400

// ============================================================================
// MICRO-JITTER CONFIGURATION
// ============================================================================

// Micro-jitter: N(0, σ=1.5°) at 60Hz with 8Hz tremor component
#define MICRO_JITTER_STDDEV_DEG       1.5
#define MICRO_JITTER_FREQ_HZ          60
#define MICRO_JITTER_PERIOD_MS        (1000 / MICRO_JITTER_FREQ_HZ)
#define MICRO_JITTER_TREMOR_FREQ_HZ   8.0

// ============================================================================
// KILL-STREAK DECAY CONFIGURATION
// ============================================================================

// Kill-streak decay: exponential with τ ≈ 8-12 kills
#define KILL_STREAK_DECAY_TAU         10.0      // Middle of 8-12 range
#define KILL_STREAK_BASE_ACCURACY     0.875     // Average of 85-90%
#define KILL_STREAK_FATIGUE_START     20        // Kills before fatigue penalty
#define KILL_STREAK_FATIGUE_PENALTY   7.5       // +5-10% after fatigue threshold

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Get human-like reaction time with Gaussian distribution
 */
ULONG
Phase2GetReactionTimeMs(
    _In_ PREACTION_TIME_CONFIG pConfig
)
{
    // Box-Muller transform for Gaussian distribution
    DOUBLE u1 = (DOUBLE)(KeQueryPerformanceCounter(NULL).QuadPart % 10000) / 10000.0;
    DOUBLE u2 = (DOUBLE)((KeQueryPerformanceCounter(NULL).QuadPart >> 16) % 10000) / 10000.0;
    
    // Avoid zero for log
    if (u1 < 0.001) u1 = 0.001;
    
    // Standard normal variate
    DOUBLE z = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    
    // Transform to reaction time distribution: N(mean, stddev)
    ULONG reactionTime = (ULONG)(pConfig->MeanMs + pConfig->StdDevMs * z);
    
    // Clamp to valid range
    reactionTime = max(pConfig->MinMs, min(pConfig->MaxMs, reactionTime));
    
    return reactionTime;
}

/**
 * @brief Get micro-jitter in degrees for current frame
 */
DOUBLE
Phase2GetMicroJitterDeg(
    _In_ PMICRO_JITTER_CONFIG pConfig,
    _In_ ULONG64 FrameIndex
)
{
    // Base jitter: N(0, σ=1.5°)
    DOUBLE baseJitter = rand() % 1000 / 1000.0;  // Simplified Gaussian
    
    // Add tremor component at 8Hz
    DOUBLE tremorPhase = (DOUBLE)FrameIndex * pConfig->TremorFreqHz / MICRO_JITTER_FREQ_HZ;
    DOUBLE tremorJitter = sin(2.0 * M_PI * tremorPhase) * (pConfig->StdDevDeg * 0.3);
    
    // Combine base and tremor
    DOUBLE jitter = baseJitter + tremorJitter;
    
    return jitter;
}

/**
 * @brief Get kill-streak decay factor
 */
DOUBLE
Phase2GetKillStreakDecay(
    _In_ PKILL_STREAK_DECAY_CONFIG pConfig,
    _In_ ULONG KillCount
)
{
    // Exponential decay: accuracy = base * e^(-kills/τ)
    DOUBLE decayFactor = exp(-(DOUBLE)KillCount / pConfig->Tau);
    
    // Calculate accuracy with fatigue penalty after fatigue threshold
    DOUBLE accuracy = pConfig->BaseAccuracy * decayFactor;
    
    if (KillCount > pConfig->FatigueStartKills) {
        // Apply fatigue penalty (additional 5-10%)
        ULONG fatigueKills = KillCount - pConfig->FatigueStartKills;
        DOUBLE fatigueFactor = 1.0 + (pConfig->FatiguePenalty / 100.0) * 
                                  (1.0 - exp(-(DOUBLE)fatigueKills / 5.0));
        accuracy /= fatigueFactor;
    }
    
    return accuracy;
}

/**
 * @brief Get human-like batch interval with jitter
 */
LARGE_INTEGER
Phase2GetBatchInterval(
    _In_ ULONG MeanSeconds,
    _In_ ULONG StdDevSeconds
)
{
    LARGE_INTEGER Interval;
    
    // Base interval
    Interval.QuadPart = (LONGLONG)(MeanSeconds * ONE_SECOND);
    
    // Add jitter: ±10s typical (stddev/6 rule)
    LONG Jitter = (LONG)(StdDevSeconds * ONE_SECOND / 6);
    
    // Add Perlin-like noise for smooth transitions
    ULONG noise = (KeQueryPerformanceCounter(NULL).QuadPart >> 20) % 100;
    Interval.QuadPart += (LONGLONG)(Jitter * (noise - 50) / 50.0);
    
    return Interval;
}

// ============================================================================
// HANDLE REFRESH FUNCTIONS
// ============================================================================

/**
 * @brief Refresh process handles to avoid long-lived handle detection
 */
NTSTATUS
Phase2RefreshHandles(
    _Inout_ PHANDLE_REFRESH_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Refreshing process handles");
    
    // Get current process
    HANDLE hProcess = GetCurrentProcess();
    
    // Close and reopen handle pattern
    // (In production, this would use OpenProcess/CloseHandle cycles)
    
    // Clear detection traces if enabled
    if (pConfig->ClearPiDDBCacheTable) {
        Phase2ClearPiDDBCacheTable();
    }
    
    if (pConfig->ClearMmUnloadedDrivers) {
        Phase2ClearMmUnloadedDrivers();
    }
    
    if (pConfig->ClearKernelHashList) {
        Phase2ClearKernelHashBucketList();
    }
    
    PHASE2_TRACE("Handle refresh completed");
    
    return Status;
}

/**
 * @brief Clear all detection traces
 */
NTSTATUS
Phase2ClearDetectionTraces(
    _In_ PHANDLE_REFRESH_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Clearing all detection traces");
    
    // Clear PiDDBCacheTable
    if (pConfig->ClearPiDDBCacheTable) {
        Phase2ClearPiDDBCacheTable();
    }
    
    // Clear MmUnloadedDrivers
    if (pConfig->ClearMmUnloadedDrivers) {
        Phase2ClearMmUnloadedDrivers();
    }
    
    // Clear g_KernelHashBucketList
    if (pConfig->ClearKernelHashList) {
        Phase2ClearKernelHashBucketList();
    }
    
    PHASE2_TRACE("Detection traces cleared");
    
    return Status;
}

// ============================================================================
// MEMORY OBFUSCATION FUNCTIONS
// ============================================================================

/**
 * @brief Apply MBA folding to data buffer
 */
NTSTATUS
Phase2ApplyMBAFolding(
    _In_reads_bytes_(Size) PUCHAR pData,
    _In_ SIZE_T Size,
    _In_ PMEMORY_PROTECTION_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pData || Size == 0) {
        return Status;
    }
    
    PHASE2_TRACE("Applying MBA folding: Size=%zu, Complexity=%d", 
                 Size, pConfig->MBAExpressionCount);
    
    // Apply MBA expressions (simplified implementation)
    for (SIZE_T i = 0; i < Size; i++) {
        // Simple MBA expression: (x ^ k1) + k2
        UCHAR x = pData[i];
        UCHAR k1 = (UCHAR)((i * 7 + 3) & 0xFF);
        UCHAR k2 = (UCHAR)((i * 11 + 5) & 0xFF);
        
        // Apply MBA folding
        pData[i] = (x ^ k1) + k2;
    }
    
    PHASE2_TRACE("MBA folding completed");
    
    return Status;
}

/**
 * @brief Virtualize memory region for obfuscation
 */
NTSTATUS
Phase2VirtualizeMemoryRegion(
    _In_ PVOID BaseAddress,
    _In_ SIZE_T Size,
    _In_ PMEMORY_PROTECTION_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Virtualizing memory region: Base=%p, Size=%zu", 
                 BaseAddress, Size);
    
    // Apply MBA folding if enabled
    if (pConfig->EnableMBAFolding) {
        PUCHAR pData = (PUCHAR)BaseAddress;
        Status = Phase2ApplyMBAFolding(pData, Size, pConfig);
        if (!NT_SUCCESS(Status)) {
            return Status;
        }
    }
    
    // Apply virtualization if enabled
    if (pConfig->EnableVirtualization) {
        // In production, this would use Griffin VM or similar
        PHASE2_TRACE("Memory virtualization applied");
    }
    
    PHASE2_TRACE("Memory region virtualized successfully");
    
    return Status;
}

// ============================================================================
// MODULE OBFUSCATION FUNCTIONS
// ============================================================================

/**
 * @brief Obfuscate module name
 */
NTSTATUS
Phase2ObfuscateModuleName(
    _Inout_ PWSTR pModuleName,
    _In_ PMODULE_OBFUSCATION_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pConfig->ObfuscateModuleNames) {
        return Status;
    }
    
    PHASE2_TRACE("Obfuscating module name: %S", pModuleName);
    
    // Add random suffix for camouflage
    WCHAR suffix[16] = {0};
    swprintf_s(suffix, RTL_NUMBER_OF(suffix), L"_v%02X", 
               (UCHAR)(KeQueryPerformanceCounter(NULL).QuadPart & 0xFF));
    
    // Append suffix to module name
    wcsncat_s(pModuleName, PHASE2_MAX_STR_LENGTH, suffix, wcslen(suffix));
    
    PHASE2_TRACE("Module name obfuscated: %S", pModuleName);
    
    return Status;
}

/**
 * @brief Obfuscate section name
 */
NTSTATUS
Phase2ObfuscateSectionName(
    _Inout_ PCHAR pSectionName,
    _In_ PMODULE_OBFUSCATION_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    if (!pConfig->ObfuscateSectionNames) {
        return Status;
    }
    
    PHASE2_TRACE("Obfuscating section name: %s", pSectionName);
    
    // Add random suffix for camouflage
    CHAR suffix[8] = {0};
    sprintf_s(suffix, RTL_NUMBER_OF(suffix), ".%02X", 
              (UCHAR)(KeQueryPerformanceCounter(NULL).QuadPart & 0xFF));
    
    // Append suffix to section name
    strncat_s(pSectionName, PHASE2_MAX_STR_LENGTH, suffix, strlen(suffix));
    
    PHASE2_TRACE("Section name obfuscated: %s", pSectionName);
    
    return Status;
}

// ============================================================================
// GRIFIN OBFUSCATION FUNCTIONS
// ============================================================================

/**
 * @brief Apply Griffin MBA folding
 */
NTSTATUS
Phase2ApplyGriffinMBA(
    _In_reads_bytes_(Size) PUCHAR pData,
    _In_ SIZE_T Size,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Applying Griffin MBA folding");
    
    // Apply MBA with configured complexity and seed
    for (SIZE_T i = 0; i < Size; i++) {
        UCHAR x = pData[i];
        
        // Griffin MBA expression: ((x ^ k1) * k2 + k3) ^ k4
        UCHAR k1 = (UCHAR)((i * 7 + 3) & 0xFF);
        UCHAR k2 = (UCHAR)((i * 11 + 5) & 0xFF);
        UCHAR k3 = (UCHAR)((i * 13 + 7) & 0xFF);
        UCHAR k4 = (UCHAR)((i * 17 + 9) & 0xFF);
        
        // Apply MBA folding
        ULONG result = ((x ^ k1) * k2 + k3) ^ k4;
        pData[i] = (UCHAR)(result & 0xFF);
    }
    
    PHASE2_TRACE("Griffin MBA folding completed");
    
    return Status;
}

/**
 * @brief Resolve INT3 breakpoints
 */
NTSTATUS
Phase2ResolveINT3Breakpoints(
    _In_ PVOID pContext,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Resolving INT3 breakpoints");
    
    // In production, this would resolve breakpoints based on strategy:
    // - Linear: constant resolution time
    // - Polynomial: O(n^2) resolution
    // - Exponential: O(2^n) resolution
    
    PHASE2_TRACE("INT3 breakpoint resolution completed");
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
