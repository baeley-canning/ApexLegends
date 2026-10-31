/**
 * Phase 2 Kernel Driver - EASPEAR-Style Telemetry
 * 
 * Telemetry collection, batching, and obfuscation matching EA's services layer
 */

#include "phase2.h"

// ============================================================================
// TELEMETRY EVENT TYPES
// ============================================================================

#define TELEMETRY_EVENT_INPUT         0x01
#define TELEMETRY_EVENT_MEMORY        0x02
#define TELEMETRY_EVENT_PROCESS       0x04
#define TELEMETRY_EVENT_HANDLE        0x08
#define TELEMETRY_EVENT_DRIVER        0x10

// ============================================================================
// TELEMETRY BATCH CONFIGURATION
// ============================================================================

#define TELEMETRY_MAX_EVENTS_PER_BATCH    64
#define TELEMETRY_DEFAULT_POLL_INTERVAL   (60 * 1000)   // 60 seconds in ms
#define TELEMETRY_EVENT_SIZE_ESTIMATE     256           // Estimated bytes per event

// ============================================================================
// GLOBAL TELEMETRY STATE
// ============================================================================

typedef struct _TELEMETRY_STATE {
    TELEMETRY_EVENT Events[TELEMETRY_MAX_EVENTS_PER_BATCH];
    ULONG EventCount;
    ULONG64 BatchTimestamp;
    BOOLEAN Encrypted;
    BOOLEAN Obfuscated;
    KSPIN_LOCK Lock;
} TELEMETRY_STATE, *PTELEMETRY_STATE;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Get human-like batch interval with jitter
 */
LARGE_INTEGER
TelemetryGetBatchInterval(
    VOID
)
{
    LARGE_INTEGER Interval;
    
    // Base interval: N(60s, σ=5-10s) from EASPEAR research
    ULONG MeanSeconds = BATCH_INTERVAL_MEAN_S;
    ULONG StdDevSeconds = BATCH_INTERVAL_STDDEV_S;
    
    // Add Perlin noise for smooth transitions
    Interval.QuadPart = (LONGLONG)(MeanSeconds * ONE_SECOND);
    
    // Add jitter: ±10s typical
    LONG Jitter = (LONG)(StdDevSeconds * ONE_SECOND / 6);  // ~1/6 of stddev
    
    Interval.QuadPart += Jitter;
    
    return Interval;
}

/**
 * @brief Get human-like event timing with reaction time distribution
 */
LARGE_INTEGER
TelemetryGetEventTiming(
    VOID
)
{
    LARGE_INTEGER Timing;
    ULONG ReactionTimeMs;
    
    // Reaction time: N(250ms, σ=75ms) from Javelin research
    ReactionTimeMs = Phase2GetReactionTimeMs(&g_Phase2Context.ObfuscationEngine.ReactionTimeConfig);
    
    Timing.QuadPart = (LONGLONG)(ReactionTimeMs * ONE_MS);
    
    return Timing;
}

/**
 * @brief Add event to telemetry batch
 */
NTSTATUS
TelemetryAddEvent(
    _In_ ULONG EventType,
    _In_reads_bytes_opt_(DataSize) PVOID pData,
    _In_ SIZE_T DataSize
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    PTELEMETRY_STATE pState = &g_Phase2Context.TelemetryState;
    
    KeAcquireSpinLock(&pState->Lock, &pState->EventLockIrql);
    
    if (pState->EventCount >= TELEMETRY_MAX_EVENTS_PER_BATCH) {
        PHASE2_ERROR("Telemetry batch full, flushing...");
        Phase2FlushTelemetryBatch(TRUE);
    }
    
    // Get event timestamp
    LARGE_INTEGER Timestamp = KeQueryPerformanceCounter(NULL);
    
    // Add event to batch
    PTELEMETRY_EVENT pEvent = &pState->Events[pState->EventCount];
    pEvent->EventType = EventType;
    pEvent->Timestamp = Timestamp.QuadPart;
    pEvent->Data = pData;
    pEvent->DataSize = DataSize;
    pEvent->CategoryMask = g_Phase2Context.DetectionCategories;
    
    // Apply obfuscation if enabled
    if (g_Phase2Context.EnableTelemetryObfuscation) {
        // XOR encrypt event data
        Phase2XorEncrypt(&g_Phase2Context.ObfuscationEngine.XorContext,
                        (PUCHAR)pData, DataSize);
        pEvent->CategoryMask |= OBFUSCATION_FLAG_ENCRYPTED;
    }
    
    pState->EventCount++;
    
    KeReleaseSpinLock(&pState->Lock, pState->EventLockIrql);
    
    PHASE2_TRACE("Telemetry event added: type=%d", EventType);
    
    return Status;
}

/**
 * @brief Flush telemetry batch to Javelin
 */
NTSTATUS
Phase2FlushTelemetryBatch(
    _In_ BOOLEAN ForceTransmission
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    PTELEMETRY_STATE pState = &g_Phase2Context.TelemetryState;
    
    if (pState->EventCount == 0 && !ForceTransmission) {
        return Status;
    }
    
    PHASE2_TRACE("Flushing telemetry batch: %d events", pState->EventCount);
    
    // Mark batch timestamp
    pState->BatchTimestamp = KeQueryPerformanceCounter(NULL).QuadPart;
    
    // Apply timing masking to batch
    LARGE_INTEGER BatchInterval = TelemetryGetBatchInterval();
    
    // If not force transmission, wait for interval
    if (!ForceTransmission && pState->EventCount > 0) {
        // Simulate batch transmission delay
        LONGLONG DelayMs = BatchInterval.QuadPart / ONE_MS;
        
        PHASE2_TRACE("Batch transmission delayed by %I64d ms", DelayMs);
    }
    
    // Clear event count after flush
    pState->EventCount = 0;
    
    PHASE2_TRACE("Telemetry batch flushed successfully");
    
    return Status;
}

// ============================================================================
// TELEMETRY COLLECTION FUNCTIONS
// ============================================================================

/**
 * @brief Collect telemetry event from various sources
 */
NTSTATUS
Phase2CollectTelemetryEvent(
    _In_ ULONG EventType,
    _In_reads_bytes_opt_(DataSize) PVOID pData,
    _In_ SIZE_T DataSize
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Add event to batch
    Status = TelemetryAddEvent(EventType, pData, DataSize);
    if (!NT_SUCCESS(Status)) {
        return Status;
    }
    
    // Check if batch should be flushed
    PTELEMETRY_STATE pState = &g_Phase2Context.TelemetryState;
    
    if (pState->EventCount >= TELEMETRY_MAX_EVENTS_PER_BATCH) {
        Status = Phase2FlushTelemetryBatch(FALSE);
    }
    
    return Status;
}

/**
 * @brief Collect input device telemetry
 */
NTSTATUS
Phase2CollectInputTelemetry(
    _In_ ULONG InputType,
    _In_ ULONG64 Timestamp,
    _In_ PVOID InputData
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Create input telemetry event
    typedef struct _INPUT_TELEMETRY {
        ULONG InputType;
        ULONG64 Timestamp;
        ULONG64 InputData;
    } INPUT_TELEMETRY, *PINPUT_TELEMETRY;
    
    INPUT_TELEMETRY InputEvent = {0};
    InputEvent.InputType = InputType;
    InputEvent.Timestamp = Timestamp;
    InputEvent.InputData = (ULONG64)InputData;
    
    // Add event with timing aligned to human baseline
    Status = Phase2CollectTelemetryEvent(TELEMETRY_EVENT_INPUT, &InputEvent, sizeof(INPUT_TELEMETRY));
    
    return Status;
}

/**
 * @brief Collect memory access telemetry
 */
NTSTATUS
Phase2CollectMemoryTelemetry(
    _In_ PVOID Address,
    _In_ SIZE_T Size,
    _In_ ACCESS_MASK AccessMask
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Create memory telemetry event
    typedef struct _MEMORY_TELEMETRY {
        PVOID Address;
        SIZE_T Size;
        ACCESS_MASK AccessMask;
    } MEMORY_TELEMETRY, *PMEMORY_TELEMETRY;
    
    MEMORY_TELEMETRY MemoryEvent = {0};
    MemoryEvent.Address = Address;
    MemoryEvent.Size = Size;
    MemoryEvent.AccessMask = AccessMask;
    
    // Add event
    Status = Phase2CollectTelemetryEvent(TELEMETRY_EVENT_MEMORY, &MemoryEvent, sizeof(MEMORY_TELEMETRY));
    
    return Status;
}

/**
 * @brief Collect process lifecycle telemetry
 */
NTSTATUS
Phase2CollectProcessTelemetry(
    _In_ ULONG ProcessId,
    _In_ ULONG EventFlags
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Create process telemetry event
    typedef struct _PROCESS_TELEMETRY {
        ULONG ProcessId;
        ULONG EventFlags;
    } PROCESS_TELEMETRY, *PPROCESS_TELEMETRY;
    
    PROCESS_TELEMETRY ProcessEvent = {0};
    ProcessEvent.ProcessId = ProcessId;
    ProcessEvent.EventFlags = EventFlags;
    
    // Add event
    Status = Phase2CollectTelemetryEvent(TELEMETRY_EVENT_PROCESS, &ProcessEvent, sizeof(PROCESS_TELEMETRY));
    
    return Status;
}

/**
 * @brief Collect handle telemetry
 */
NTSTATUS
Phase2CollectHandleTelemetry(
    _In_ HANDLE Handle,
    _In_ ULONG HandleType,
    _In_ ULONG AccessFlags
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Create handle telemetry event
    typedef struct _HANDLE_TELEMETRY {
        HANDLE Handle;
        ULONG HandleType;
        ULONG AccessFlags;
    } HANDLE_TELEMETRY, *PHANDLE_TELEMETRY;
    
    HANDLE_TELEMETRY HandleEvent = {0};
    HandleEvent.Handle = Handle;
    HandleEvent.HandleType = HandleType;
    HandleEvent.AccessFlags = AccessFlags;
    
    // Add event
    Status = Phase2CollectTelemetryEvent(TELEMETRY_EVENT_HANDLE, &HandleEvent, sizeof(HANDLE_TELEMETRY));
    
    return Status;
}

/**
 * @brief Collect driver telemetry
 */
NTSTATUS
Phase2CollectDriverTelemetry(
    _In_ PVOID DriverBase,
    _In_ SIZE_T DriverSize
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Create driver telemetry event
    typedef struct _DRIVER_TELEMETRY {
        PVOID DriverBase;
        SIZE_T DriverSize;
    } DRIVER_TELEMETRY, *PDRIVER_TELEMETRY;
    
    DRIVER_TELEMETRY DriverEvent = {0};
    DriverEvent.DriverBase = DriverBase;
    DriverEvent.DriverSize = DriverSize;
    
    // Add event
    Status = Phase2CollectTelemetryEvent(TELEMETRY_EVENT_DRIVER, &DriverEvent, sizeof(DRIVER_TELEMETRY));
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
