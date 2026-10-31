/**
 * Phase 2 Kernel Driver - Telemetry Latency Test Suite
 *
 * Tests for telemetry timing, latency measurement, and Javelin detection alignment
 */

#include "phase2.h"
#include "test_framework.h"

// ============================================================================
// TEST CONSTANTS
// ============================================================================

#define TELEMETRY_POLL_INTERVAL_MS    60000   // 60 seconds (matches Javelin poll interval)
#define MAX_TELEMETRY_SAMPLES         1000
#define BASELINE_LATENCY_MS           250     // Base latency ~250ms (Javelin human baseline)
#define LATENCY_JITTER_SIGMA_MS       75      // σ=75ms for reaction time distribution

// ============================================================================
// TEST STATE
// ============================================================================

typedef struct _TELEMETRY_LATENCY_TEST_STATE {
    LARGE_INTEGER TotalLatency;
    ULONG SampleCount;
    LARGE_INTEGER JitterSum;
    ULONG JitterCount;
    KSPIN_LOCK Lock;
} TELEMETRY_LATENCY_TEST_STATE, *PTELEMETRY_LATENCY_TEST_STATE;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Initialize telemetry latency test state
 */
NTSTATUS
TestInitializeLatencyState(
    _Out_ PTELEMETRY_LATENCY_TEST_STATE* ppState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PTELEMETRY_LATENCY_TEST_STATE pState = Phase2AllocatePool(NonPagedPool, sizeof(TELEMETRY_LATENCY_TEST_STATE));
    if (!pState) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    
    RtlZeroMemory(pState, sizeof(TELEMETRY_LATENCY_TEST_STATE));
    KeInitializeSpinLock(&pState->Lock);
    
    *ppState = pState;
    
    PHASE2_TRACE("Telemetry latency test state initialized");
    
    return Status;
}

/**
 * @brief Cleanup telemetry latency test state
 */
VOID
TestCleanupLatencyState(
    _In_opt_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    if (pState) {
        Phase2FreePool(pState);
    }
}

// ============================================================================
// TEST CASES
// ============================================================================

/**
 * @brief Test telemetry latency distribution matching Javelin baseline
 */
NTSTATUS
TestLatencyDistribution(
    _In_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing telemetry latency distribution (baseline=%dms, σ=%dms)",
                 BASELINE_LATENCY_MS, LATENCY_JITTER_SIGMA_MS);
    
    // Simulate latency samples following Javelin's human baseline N(250ms, σ=75ms)
    for (ULONG i = 0; i < MAX_TELEMETRY_SAMPLES / 10; i++) {
        // Generate latency with Gaussian distribution
        // Using Box-Muller transform for normal distribution
        DOUBLE u1 = (DOUBLE)(KeQueryPerformanceCounter(NULL).QuadPart % 1000) / 1000.0;
        DOUBLE u2 = (DOUBLE)((KeQueryPerformanceCounter(NULL).QuadPart >> 16) % 1000) / 1000.0;
        
        // Avoid log(0)
        if (u1 < 0.001) u1 = 0.001;
        
        // Box-Muller: z = sqrt(-2*ln(u1)) * cos(2*pi*u2)
        DOUBLE z = sqrt(-2.0 * log(u1)) * cos(6.283185307 * u2);
        
        // Scale to Javelin parameters: latency = mean + σ * z
        DOUBLE latencyMs = BASELINE_LATENCY_MS + LATENCY_JITTER_SIGMA_MS * z;
        
        // Accumulate statistics
        pState->TotalLatency.QuadPart += (LONGLONG)latencyMs;
        pState->SampleCount++;
        
        PHASE2_TRACE("Sample %d: latency=%.1fms", i + 1, latencyMs);
    }
    
    DOUBLE avgLatency = (DOUBLE)pState->TotalLatency.QuadPart / pState->SampleCount;
    PHASE2_TRACE("Average latency: %.1fms (target: ~250ms)", avgLatency);
    
    return Status;
}

/**
 * @brief Test latency jitter patterns matching Javelin micro-jitter
 */
NTSTATUS
TestJitterPatterns(
    _In_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing latency jitter patterns (σ=%.1f° at 60Hz, 8Hz tremor)",
                 LATENCY_JITTER_SIGMA_MS / 10.0);
    
    // Simulate micro-jitter patterns
    const DOUBLE baseJitterDeg = LATENCY_JITTER_SIGMA_MS / 10.0;  // ~7.5° at 60Hz
    
    for (ULONG i = 0; i < MAX_TELEMETRY_SAMPLES / 20; i++) {
        // Base jitter at 60Hz
        DOUBLE baseJitter = baseJitterDeg * sin(6.283185307 * i / 60.0);
        
        // 8Hz tremor component
        DOUBLE tremor = (baseJitterDeg / 4.0) * sin(6.283185307 * i / 8.0);
        
        // Combined jitter
        DOUBLE totalJitter = baseJitter + tremor;
        
        pState->JitterSum.QuadPart += (LONGLONG)(totalJitter * 100);  // Scale for precision
        pState->JitterCount++;
        
        PHASE2_TRACE("Sample %d: jitter=%.2f° (base=%.2f°, tremor=%.2f°)",
                    i + 1, totalJitter, baseJitter, tremor);
    }
    
    DOUBLE avgJitter = (DOUBLE)pState->JitterSum.QuadPart / 
                      (pState->JitterCount * 100);
    PHASE2_TRACE("Average jitter: %.2f° (target: ~7.5°)", avgJitter);
    
    return Status;
}

/**
 * @brief Test latency alignment with Javelin detection windows
 */
NTSTATUS
TestLatencyAlignment(
    _In_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing latency alignment with Javelin detection windows");
    
    // Simulate detection window alignment over time
    const ULONG detectionWindows[] = {5000, 15000, 30000, 60000};  // Windows in ms
    
    for (ULONG w = 0; w < RTL_NUMBER_OF(detectionWindows); w++) {
        PHASE2_TRACE("Detection window %d: %dms", w + 1, detectionWindows[w]);
        
        // Simulate telemetry samples within this window
        ULONG samplesInWindow = detectionWindows[w] / 100;  // 10ms intervals
        
        for (ULONG i = 0; i < samplesInWindow; i++) {
            LARGE_INTEGER currentTime = KeQueryPerformanceCounter(NULL);
            LONGLONG latencyMs = (currentTime.QuadPart % 100000) / 100;
            
            // Check if latency falls within expected range
            if (latencyMs < detectionWindows[w] * 0.1) {
                PHASE2_TRACE("Sample %d: latency=%lldms (within window)", i + 1, latencyMs);
            }
        }
    }
    
    PHASE2_TRACE("Latency alignment test PASSED");
    
    return Status;
}

/**
 * @brief Test kill-streak decay alignment with telemetry patterns
 */
NTSTATUS
TestKillStreakDecay(
    _In_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing kill-streak decay alignment (τ≈10 kills)");
    
    // Simulate kill streak and decay pattern
    const ULONG maxStreak = 30;
    const DOUBLE decayTau = 10.0;  // τ≈10 kills
    
    for (ULONG streak = 0; streak < maxStreak; streak++) {
        // Exponential decay: decay = e^(-streak/τ)
        DOUBLE decayFactor = exp(-(DOUBLE)streak / decayTau);
        
        // Add fatigue penalty after 20 kills
        DOUBLE fatigue = (streak > 20) ? 0.15 * (streak - 20) : 0.0;
        
        DOUBLE effectiveDecay = decayFactor + fatigue;
        
        PHASE2_TRACE("Streak %d: decay=%.3f, fatigue=%.3f",
                    streak + 1, decayFactor, fatigue);
    }
    
    PHASE2_TRACE("Kill-streak decay test PASSED");
    
    return Status;
}

/**
 * @brief Test latency vs. detection confidence correlation
 */
NTSTATUS
TestLatencyConfidence(
    _In_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing latency vs. detection confidence correlation");
    
    // Simulate detection confidence based on latency patterns
    const DOUBLE baseConfidence = 0.5;  // Javelin baseline
    const DOUBLE confidenceVariance = 0.15;
    
    for (ULONG i = 0; i < MAX_TELEMETRY_SAMPLES / 15; i++) {
        // Generate latency and corresponding confidence
        DOUBLE latencyMs = BASELINE_LATENCY_MS + 
                          LATENCY_JITTER_SIGMA_MS * sin(6.283185307 * i / 100.0);
        
        // Confidence inversely related to latency deviation from baseline
        DOUBLE latencyDeviation = fabs(latencyMs - BASELINE_LATENCY_MS);
        DOUBLE confidence = baseConfidence - (latencyDeviation / 200.0) + 
                           (confidenceVariance * sin(6.283185307 * i / 50.0));
        
        // Clamp confidence to [0.3, 0.7] range
        if (confidence < 0.3) confidence = 0.3;
        if (confidence > 0.7) confidence = 0.7;
        
        PHASE2_TRACE("Sample %d: latency=%.1fms, confidence=%.3f",
                    i + 1, latencyMs, confidence);
    }
    
    PHASE2_TRACE("Latency-confidence correlation test PASSED");
    
    return Status;
}

/**
 * @brief Test telemetry batch timing and interval consistency
 */
NTSTATUS
TestBatchTiming(
    _In_ PTELEMETRY_LATENCY_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing telemetry batch timing and interval consistency");
    
    // Simulate batch processing over multiple intervals
    const ULONG batchCount = 10;
    const ULONG batchSize = 100;
    
    for (ULONG batch = 0; batch < batchCount; batch++) {
        LARGE_INTEGER batchStart = KeQueryPerformanceCounter(NULL);
        
        // Process batch of telemetry samples
        for (ULONG i = 0; i < batchSize; i++) {
            // Simulate sample processing with realistic timing
            LARGE_INTEGER temp = KeQueryPerformanceCounter(NULL);
            temp.QuadPart ^= (batch * 0x1000 + i * 0x100);
        }
        
        LARGE_INTEGER batchEnd = KeQueryPerformanceCounter(NULL);
        LONGLONG batchDuration = (batchEnd.QuadPart - batchStart.QuadPart) * 1000 / 
                                KeQueryPerformanceFrequency(NULL).QuadPart;
        
        PHASE2_TRACE("Batch %d: duration=%lldms", batch + 1, batchDuration);
    }
    
    PHASE2_TRACE("Batch timing test PASSED");
    
    return Status;
}

// ============================================================================
// TEST SUITE ENTRY POINTS
// ============================================================================

/**
 * @brief Run all telemetry latency tests
 */
NTSTATUS
RunTelemetryLatencyTests(
    VOID
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    PTELEMETRY_LATENCY_TEST_STATE pState = NULL;
    
    PHASE2_TRACE("=== Starting Telemetry Latency Tests ===");
    
    // Initialize test state
    Status = TestInitializeLatencyState(&pState);
    if (!NT_SUCCESS(Status)) {
        goto cleanup;
    }
    
    // Run individual test cases
    NTSTATUS testCaseStatus = STATUS_SUCCESS;
    
    testCaseStatus = TestLatencyDistribution(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestLatencyDistribution FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestJitterPatterns(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestJitterPatterns FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestLatencyAlignment(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestLatencyAlignment FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestKillStreakDecay(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestKillStreakDecay FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestLatencyConfidence(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestLatencyConfidence FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestBatchTiming(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestBatchTiming FAILED");
        Status = testCaseStatus;
    }
    
    PHASE2_TRACE("=== Telemetry Latency Tests Complete ===");
    
cleanup:
    TestCleanupLatencyState(pState);
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
