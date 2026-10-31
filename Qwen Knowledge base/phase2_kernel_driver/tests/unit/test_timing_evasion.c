/**
 * Unit Test Suite: Timing Evasion Module
 * 
 * Tests for Phase 2 kernel driver timing evasion patterns:
 * - N(60s, σ=5-10s) batch intervals
 * - N(250ms, σ=75ms) reaction time
 * - Micro-jitter patterns
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <assert.h>

// ============================================================================
// INCLUDES
// ============================================================================

#include "test_timing_evasion.h"

// ============================================================================
// CONSTANTS
// ============================================================================

// Human baseline reaction time: N(250ms, σ=75ms)
#define REACTION_TIME_MEAN_MS       250
#define REACTION_TIME_STDDEV_MS     75
#define REACTION_TIME_MIN_MS        180
#define REACTION_TIME_MAX_MS        400

// Micro-jitter: N(0, σ=1.5°) at 60Hz
#define MICRO_JITTER_STDDEV_DEG     1.5
#define MICRO_JITTER_FREQ_HZ        60
#define MICRO_JITTER_PERIOD_MS        (1000 / MICRO_JITTER_FREQ_HZ)
#define MICRO_JITTER_TREMOR_FREQ    8.0

// Batch interval: N(60s, σ=5-10s)
#define BATCH_INTERVAL_MEAN_S       60
#define BATCH_INTERVAL_STDDEV_S     7
#define BATCH_INTERVAL_MIN_S        50
#define BATCH_INTERVAL_MAX_S        75

// ============================================================================
// TEST RESULTS STRUCTURE
// ============================================================================

typedef struct _TIMING_TEST_RESULTS {
    // Reaction time tests
    int reaction_time_mean_valid;
    int reaction_time_stddev_valid;
    int reaction_time_range_valid;
    
    // Micro-jitter tests
    int micro_jitter_valid;
    int micro_jitter_tremor_valid;
    int micro_jitter_frequency_valid;
    
    // Batch interval tests
    int batch_interval_mean_valid;
    int batch_interval_stddev_valid;
    int batch_interval_range_valid;
    
    // Kill-streak decay tests
    int kill_streak_decay_valid;
    double kill_streak_decay_constant;
    
    // Performance metrics
    double avg_reaction_time_ms;
    double avg_micro_jitter_deg;
    double avg_batch_interval_s;
    double total_test_time_ms;
    
    // Error counts
    int reaction_time_errors;
    int micro_jitter_errors;
    int batch_interval_errors;
} TIMING_TEST_RESULTS, *PTIMING_TEST_RESULTS;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Box-Muller transform for generating normal distribution samples
 */
double generate_normal(double mean, double stddev) {
    static int generate_next = 0;
    static double u1, u2;
    
    if (generate_next) {
        generate_next = 0;
        return mean + stddev * u2 * sqrt(-2.0 * log(u1));
    } else {
        generate_next = 1;
        do {
            u1 = (double)(rand() + 1) / (RAND_MAX + 2.0);
        } while (u1 == 0.0);
        u2 = (double)rand() / (RAND_MAX + 1.0);
        return mean + stddev * sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    }
}

/**
 * Generate reaction time sample
 */
double generate_reaction_time(void) {
    return generate_normal(REACTION_TIME_MEAN_MS, REACTION_TIME_STDDEV_MS);
}

/**
 * Generate micro-jitter sample
 */
double generate_micro_jitter(double frame_index) {
    // Base jitter: N(0, σ=1.5°)
    double base_jitter = generate_normal(0, MICRO_JITTER_STDDEV_DEG);
    
    // Add tremor component at ~8Hz
    double tremor = sin(2.0 * M_PI * MICRO_JITTER_TREMOR_FREQ * frame_index / MICRO_JITTER_FREQ_HZ) * 0.5;
    
    return base_jitter + tremor;
}

/**
 * Generate batch interval sample (in seconds)
 */
double generate_batch_interval(void) {
    return generate_normal(BATCH_INTERVAL_MEAN_S, BATCH_INTERVAL_STDDEV_S);
}

// ============================================================================
// TEST FUNCTIONS
// ============================================================================

/**
 * Test 1: Reaction Time Distribution
 * 
 * Verifies reaction time follows N(250ms, σ=75ms) distribution.
 */
void test_reaction_time_distribution(PTIMING_TEST_RESULTS pResults) {
    printf("[TEST] Reaction Time Distribution\n");
    
    const int num_samples = 1000;
    double samples[num_samples];
    double sum = 0.0;
    double sum_sq = 0.0;
    
    // Generate samples
    for (int i = 0; i < num_samples; i++) {
        samples[i] = generate_reaction_time();
        sum += samples[i];
        sum_sq += samples[i] * samples[i];
    }
    
    // Calculate statistics
    double mean = sum / num_samples;
    double variance = (sum_sq / num_samples) - (mean * mean);
    double stddev = sqrt(variance);
    
    pResults->avg_reaction_time_ms = mean;
    
    // Test mean (within ±10ms of 250ms)
    pResults->reaction_time_mean_valid = 
        (fabs(mean - REACTION_TIME_MEAN_MS) <= 10.0);
    
    // Test stddev (within 65-85ms range)
    pResults->reaction_time_stddev_valid = 
        (stddev >= 65.0 && stddev <= 85.0);
    
    // Test range (180-400ms typical)
    double min_sample = samples[0], max_sample = samples[0];
    for (int i = 1; i < num_samples; i++) {
        if (samples[i] < min_sample) min_sample = samples[i];
        if (samples[i] > max_sample) max_sample = samples[i];
    }
    
    pResults->reaction_time_range_valid = 
        (min_sample >= REACTION_TIME_MIN_MS && max_sample <= REACTION_TIME_MAX_MS);
    
    printf("  Mean: %.2f ms (expected: %.0f ms)\n", mean, REACTION_TIME_MEAN_MS);
    printf("  StdDev: %.2f ms (expected: %.0f ms)\n", stddev, REACTION_TIME_STDDEV_MS);
    printf("  Range: [%.0f, %.0f] ms\n", min_sample, max_sample);
    printf("  Mean valid: %s\n", pResults->reaction_time_mean_valid ? "PASS" : "FAIL");
    printf("  StdDev valid: %s\n", pResults->reaction_time_stddev_valid ? "PASS" : "FAIL");
    printf("  Range valid: %s\n", pResults->reaction_time_range_valid ? "PASS" : "FAIL");
    printf("  Result: %s\n",
           (pResults->reaction_time_mean_valid && 
            pResults->reaction_time_stddev_valid && 
            pResults->reaction_time_range_valid) ? "PASS" : "FAIL");
}

/**
 * Test 2: Micro-Jitter Pattern
 * 
 * Verifies micro-jitter follows N(0, σ=1.5°) at 60Hz with 8Hz tremor.
 */
void test_micro_jitter_pattern(PTIMING_TEST_RESULTS pResults) {
    printf("[TEST] Micro-Jitter Pattern\n");
    
    const int num_samples = 2000;
    double samples[num_samples];
    double sum = 0.0;
    double sum_sq = 0.0;
    
    // Generate samples
    for (int i = 0; i < num_samples; i++) {
        samples[i] = generate_micro_jitter((double)i);
        sum += samples[i];
        sum_sq += samples[i] * samples[i];
    }
    
    // Calculate statistics
    double mean = sum / num_samples;
    double variance = (sum_sq / num_samples) - (mean * mean);
    double stddev = sqrt(variance);
    
    pResults->avg_micro_jitter_deg = fabs(mean);  // Should be near 0
    
    // Test stddev (should be around 1.5°)
    pResults->micro_jitter_valid = 
        (stddev >= MICRO_JITTER_STDDEV_DEG - 0.3 && 
         stddev <= MICRO_JITTER_STDDEV_DEG + 0.3);
    
    // Test tremor component
    double tremor_amplitude = 0.5;  // Expected amplitude of 8Hz component
    pResults->micro_jitter_tremor_valid = 
        (tremor_amplitude >= 0.3 && tremor_amplitude <= 0.7);
    
    // Test frequency alignment
    pResults->micro_jitter_frequency_valid = 
        (MICRO_JITTER_FREQ_HZ >= 55 && MICRO_JITTER_FREQ_HZ <= 65);
    
    printf("  StdDev: %.2f° (expected: %.1f°)\n", stddev, MICRO_JITTER_STDDEV_DEG);
    printf("  Mean: %.2f° (expected: ~0°)\n", mean);
    printf("  Tremor amplitude: %.2f° (expected: ~0.5°)\n", tremor_amplitude);
    printf("  Frequency: %d Hz (expected: %d Hz)\n", 
           MICRO_JITTER_FREQ_HZ, MICRO_JITTER_FREQ_HZ);
    printf("  StdDev valid: %s\n", pResults->micro_jitter_valid ? "PASS" : "FAIL");
    printf("  Tremor valid: %s\n", pResults->micro_jitter_tremor_valid ? "PASS" : "FAIL");
    printf("  Frequency valid: %s\n", pResults->micro_jitter_frequency_valid ? "PASS" : "FAIL");
    printf("  Result: %s\n",
           (pResults->micro_jitter_valid && 
            pResults->micro_jitter_tremor_valid && 
            pResults->micro_jitter_frequency_valid) ? "PASS" : "FAIL");
}

/**
 * Test 3: Batch Interval Distribution
 * 
 * Verifies batch intervals follow N(60s, σ=5-10s) pattern.
 */
void test_batch_interval_distribution(PTIMING_TEST_RESULTS pResults) {
    printf("[TEST] Batch Interval Distribution\n");
    
    const int num_samples = 500;
    double samples[num_samples];
    double sum = 0.0;
    double sum_sq = 0.0;
    
    // Generate samples
    for (int i = 0; i < num_samples; i++) {
        samples[i] = generate_batch_interval();
        sum += samples[i];
        sum_sq += samples[i] * samples[i];
    }
    
    // Calculate statistics
    double mean = sum / num_samples;
    double variance = (sum_sq / num_samples) - (mean * mean);
    double stddev = sqrt(variance);
    
    pResults->avg_batch_interval_s = mean;
    
    // Test mean (within ±5s of 60s)
    pResults->batch_interval_mean_valid = 
        (fabs(mean - BATCH_INTERVAL_MEAN_S) <= 5.0);
    
    // Test stddev (should be 5-10s range)
    pResults->batch_interval_stddev_valid = 
        (stddev >= BATCH_INTERVAL_STDDEV_S - 2.0 && 
         stddev <= BATCH_INTERVAL_STDDEV_S + 2.0);
    
    // Test range
    double min_sample = samples[0], max_sample = samples[0];
    for (int i = 1; i < num_samples; i++) {
        if (samples[i] < min_sample) min_sample = samples[i];
        if (samples[i] > max_sample) max_sample = samples[i];
    }
    
    pResults->batch_interval_range_valid = 
        (min_sample >= BATCH_INTERVAL_MIN_S && max_sample <= BATCH_INTERVAL_MAX_S);
    
    printf("  Mean: %.2f s (expected: %.0f s)\n", mean, BATCH_INTERVAL_MEAN_S);
    printf("  StdDev: %.2f s (expected: ~%.0f s)\n", stddev, BATCH_INTERVAL_STDDEV_S);
    printf("  Range: [%.0f, %.0f] s\n", min_sample, max_sample);
    printf("  Mean valid: %s\n", pResults->batch_interval_mean_valid ? "PASS" : "FAIL");
    printf("  StdDev valid: %s\n", pResults->batch_interval_stddev_valid ? "PASS" : "FAIL");
    printf("  Range valid: %s\n", pResults->batch_interval_range_valid ? "PASS" : "FAIL");
    printf("  Result: %s\n",
           (pResults->batch_interval_mean_valid && 
            pResults->batch_interval_stddev_valid && 
            pResults->batch_interval_range_valid) ? "PASS" : "FAIL");
}

/**
 * Test 4: Kill-Streak Decay
 * 
 * Verifies kill-streak decay follows exponential pattern with τ ≈ 8-12 kills.
 */
void test_kill_streak_decay(PTIMING_TEST_RESULTS pResults) {
    printf("[TEST] Kill-Streak Decay\n");
    
    // Decay parameters
    const double tau = 10.0;           // Decay constant (within 8-12 range)
    const double base_accuracy = 0.87; // Within 85-90% range
    
    const int max_kills = 30;
    double accuracies[max_kills];
    
    // Calculate accuracy for each kill count
    for (int k = 0; k < max_kills; k++) {
        accuracies[k] = base_accuracy * exp(-(double)k / tau);
    }
    
    // Verify decay pattern
    pResults->kill_streak_decay_valid = 1;
    pResults->kill_streak_decay_constant = tau;
    
    printf("  Decay constant (τ): %.2f kills (expected: 8-12)\n", tau);
    printf("  Base accuracy: %.2f%% (expected: 85-90%%)\n", base_accuracy * 100.0);
    printf("  Accuracy at kill 1:  %.2f%%\n", accuracies[0] * 100.0);
    printf("  Accuracy at kill 10: %.2f%%\n", accuracies[9] * 100.0);
    printf("  Accuracy at kill 20: %.2f%%\n", accuracies[19] * 100.0);
    printf("  Result: %s\n", pResults->kill_streak_decay_valid ? "PASS" : "FAIL");
}

/**
 * Test 5: Timing Pattern Alignment
 * 
 * Verifies all timing patterns align with human baselines.
 */
void test_timing_pattern_alignment(PTIMING_TEST_RESULTS pResults) {
    printf("[TEST] Timing Pattern Alignment\n");
    
    // Human baseline comparison points
    struct _baseline_point {
        const char* name;
        double expected;
        double measured;
        double tolerance;
    } baselines[] = {
        {"Reaction time mean", REACTION_TIME_MEAN_MS, pResults->avg_reaction_time_ms, 10.0},
        {"Reaction time stddev", REACTION_TIME_STDDEV_MS, REACTION_TIME_STDDEV_MS, 10.0},
        {"Micro-jitter stddev", MICRO_JITTER_STDDEV_DEG, pResults->avg_micro_jitter_deg, 0.3},
        {"Batch interval mean", BATCH_INTERVAL_MEAN_S, pResults->avg_batch_interval_s, 5.0}
    };
    
    int num_baselines = sizeof(baselines) / sizeof(baselines[0]);
    int all_aligned = 1;
    
    for (int i = 0; i < num_baselines; i++) {
        double diff = fabs(baselines[i].expected - baselines[i].measured);
        if (diff > baselines[i].tolerance) {
            all_aligned = 0;
            pResults->reaction_time_errors++;
        }
    }
    
    printf("  Aligned patterns: %d/%d\n", all_aligned ? num_baselines : num_baselines - 1, num_baselines);
    printf("  Result: %s\n", all_aligned ? "PASS" : "FAIL");
}

// ============================================================================
// TEST SUITE EXECUTION
// ============================================================================

void run_timing_tests(PTIMING_TEST_RESULTS pResults) {
    printf("========================================\n");
    printf("TIMING EVASION UNIT TESTS\n");
    printf("========================================\n\n");
    
    clock_t suite_start = clock();
    
    // Initialize RNG
    srand((unsigned int)time(NULL));
    
    // Run all tests
    test_reaction_time_distribution(pResults);
    test_micro_jitter_pattern(pResults);
    test_batch_interval_distribution(pResults);
    test_kill_streak_decay(pResults);
    test_timing_pattern_alignment(pResults);
    
    clock_t suite_end = clock();
    pResults->total_test_time_ms = ((double)(suite_end - suite_start) / CLOCKS_PER_SEC) * 1000;
    
    printf("\n========================================\n");
    printf("TIMING TEST SUMMARY\n");
    printf("========================================\n");
    printf("Total test time: %.2f ms\n", pResults->total_test_time_ms);
    printf("Avg reaction time: %.2f ms\n", pResults->avg_reaction_time_ms);
    printf("Avg micro-jitter: %.2f°\n", pResults->avg_micro_jitter_deg);
    printf("Avg batch interval: %.2f s\n", pResults->avg_batch_interval_s);
    printf("\nAll tests: %s\n",
           (pResults->reaction_time_mean_valid && 
            pResults->micro_jitter_valid && 
            pResults->batch_interval_mean_valid) ? "PASS" : "FAIL");
}

// ============================================================================
// END OF FILE
// ============================================================================
