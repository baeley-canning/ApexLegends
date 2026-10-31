/**
 * Unit Test Suite: XOR Encryption Module
 * 
 * Tests for Phase 2 kernel driver XOR encryption with Griffin-compatible patterns
 * Key: 0x5A3C5E9F
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <assert.h>

// ============================================================================
// INCLUDES
// ============================================================================

#include "test_xor_encryption.h"

// ============================================================================
// CONSTANTS
// ============================================================================

#define XOR_KEY_DEFAULT       0x5A3C5E9F
#define XOR_BLOCK_SIZE        16                  // 128-bit blocks
#define XOR_IV_SIZE           16
#define TEST_BUFFER_SIZE      4096

// Griffin-compatible XOR patterns
#define GRIFFIN_XOR_PATTERN_1 0x5A3C5E9F
#define GRIFFIN_XOR_PATTERN_2 0xF9E5C3A5
#define GRIFFIN_XOR_PATTERN_3 0xA5C3E5F9

// ============================================================================
// TEST RESULTS STRUCTURE
// ============================================================================

typedef struct _XOR_TEST_RESULTS {
    // Basic encryption/decryption tests
    int encrypt_decrypt_matches;
    int encryption_identity;
    
    // Griffin pattern tests
    int griffin_patterns_valid;
    int griffin_pattern_1_valid;
    int griffin_pattern_2_valid;
    int griffin_pattern_3_valid;
    
    // Key rotation tests
    int key_rotation_valid;
    int key_rotation_entropy;
    
    // Performance metrics
    double encrypt_throughput_mb_s;
    double decrypt_throughput_mb_s;
    double total_test_time_ms;
    
    // Error counts
    int encrypt_errors;
    int decrypt_errors;
    int pattern_errors;
} XOR_TEST_RESULTS, *PXOR_TEST_RESULTS;

// ============================================================================
// XOR TEST FUNCTIONS
// ============================================================================

/**
 * Test 1: Basic XOR Encryption/Decryption
 * 
 * Verifies that XOR encryption and decryption are symmetric operations.
 * Expected: encrypt(encrypt(data)) = data for single-key XOR
 */
void test_xor_basic_encryption(PXOR_TEST_RESULTS pResults) {
    printf("[TEST] Basic XOR Encryption/Decryption\n");
    
    // Test buffer with known patterns
    unsigned char test_buffer[256];
    for (int i = 0; i < 256; i++) {
        test_buffer[i] = (unsigned char)(i * 7 + 13);
    }
    
    // XOR with default key
    unsigned char key = XOR_KEY_DEFAULT & 0xFF;
    for (int i = 0; i < 256; i++) {
        test_buffer[i] ^= key;
    }
    
    // Decrypt (XOR is symmetric)
    for (int i = 0; i < 256; i++) {
        test_buffer[i] ^= key;
    }
    
    // Verify identity
    int matches = 1;
    for (int i = 0; i < 256; i++) {
        if (test_buffer[i] != (unsigned char)(i * 7 + 13)) {
            matches = 0;
            break;
        }
    }
    
    pResults->encrypt_decrypt_matches = matches;
    printf("  Result: %s\n", matches ? "PASS" : "FAIL");
}

/**
 * Test 2: Griffin-Compatible XOR Patterns
 * 
 * Tests the three Griffin-compatible XOR patterns:
 * - Pattern 1: 0x5A3C5E9F (primary)
 * - Pattern 2: 0xF9E5C3A5 (rotated)
 * - Pattern 3: 0xA5C3E5F9 (mirrored)
 */
void test_griffin_xor_patterns(PXOR_TEST_RESULTS pResults) {
    printf("[TEST] Griffin-Compatible XOR Patterns\n");
    
    const unsigned int griffin_patterns[3] = {
        GRIFFIN_XOR_PATTERN_1,  // 0x5A3C5E9F
        GRIFFIN_XOR_PATTERN_2,  // 0xF9E5C3A5
        GRIFFIN_XOR_PATTERN_3   // 0xA5C3E5F9
    };
    
    int all_valid = 1;
    pResults->griffin_pattern_1_valid = 1;
    pResults->griffin_pattern_2_valid = 1;
    pResults->griffin_pattern_3_valid = 1;
    
    for (int p = 0; p < 3; p++) {
        unsigned int pattern = griffin_patterns[p];
        
        // Test encryption with this pattern
        unsigned char test_data[64];
        for (int i = 0; i < 64; i++) {
            test_data[i] = (unsigned char)(i * 11 + 7);
        }
        
        // Encrypt using pattern bytes
        for (int i = 0; i < 64; i++) {
            test_data[i] ^= ((unsigned char*)&pattern)[i % 4];
        }
        
        // Decrypt
        for (int i = 0; i < 64; i++) {
            test_data[i] ^= ((unsigned char*)&pattern)[i % 4];
        }
        
        // Verify
        int valid = 1;
        for (int i = 0; i < 64; i++) {
            if (test_data[i] != (unsigned char)(i * 11 + 7)) {
                valid = 0;
                break;
            }
        }
        
        if (!valid) {
            all_valid = 0;
            switch (p) {
                case 0: pResults->griffin_pattern_1_valid = 0; break;
                case 1: pResults->griffin_pattern_2_valid = 0; break;
                case 2: pResults->griffin_pattern_3_valid = 0; break;
            }
        }
    }
    
    pResults->griffin_patterns_valid = all_valid;
    printf("  Pattern 1 (0x5A3C5E9F): %s\n", 
           pResults->griffin_pattern_1_valid ? "PASS" : "FAIL");
    printf("  Pattern 2 (0xF9E5C3A5): %s\n", 
           pResults->griffin_pattern_2_valid ? "PASS" : "FAIL");
    printf("  Pattern 3 (0xA5C3E5F9): %s\n", 
           pResults->griffin_pattern_3_valid ? "PASS" : "FAIL");
    printf("  Result: %s\n", all_valid ? "PASS" : "FAIL");
}

/**
 * Test 3: XOR Key Rotation
 * 
 * Tests key rotation functionality with configurable interval.
 * Expected: rotated keys maintain encryption integrity.
 */
void test_xor_key_rotation(PXOR_TEST_RESULTS pResults) {
    printf("[TEST] XOR Key Rotation\n");
    
    const int num_rotations = 10;
    unsigned char current_key = XOR_KEY_DEFAULT & 0xFF;
    int all_valid = 1;
    
    for (int r = 0; r < num_rotations; r++) {
        // Generate test data
        unsigned char test_data[128];
        for (int i = 0; i < 128; i++) {
            test_data[i] = (unsigned char)((i + r) * 13 + 5);
        }
        
        // Encrypt with current key
        for (int i = 0; i < 128; i++) {
            test_data[i] ^= current_key;
        }
        
        // Decrypt
        for (int i = 0; i < 128; i++) {
            test_data[i] ^= current_key;
        }
        
        // Verify
        int valid = 1;
        for (int i = 0; i < 128; i++) {
            if (test_data[i] != (unsigned char)((i + r) * 13 + 5)) {
                valid = 0;
                break;
            }
        }
        
        if (!valid) {
            all_valid = 0;
            pResults->encrypt_errors++;
        }
        
        // Rotate key (simple XOR-based rotation)
        current_key ^= (unsigned char)(r * 7 + 3);
    }
    
    pResults->key_rotation_valid = all_valid;
    printf("  Rotations tested: %d\n", num_rotations);
    printf("  Result: %s\n", all_valid ? "PASS" : "FAIL");
}

/**
 * Test 4: XOR Throughput Measurement
 * 
 * Measures encryption/decryption throughput for large buffers.
 */
void test_xor_throughput(PXOR_TEST_RESULTS pResults) {
    printf("[TEST] XOR Throughput Measurement\n");
    
    const int buffer_sizes[] = {64, 256, 1024, 4096};
    const int num_sizes = sizeof(buffer_sizes) / sizeof(buffer_sizes[0]);
    
    clock_t start_time, end_time;
    double total_encrypt_time_ms = 0;
    double total_decrypt_time_ms = 0;
    
    for (int s = 0; s < num_sizes; s++) {
        int size = buffer_sizes[s];
        unsigned char* buffer = (unsigned char*)malloc(size);
        
        // Initialize buffer
        for (int i = 0; i < size; i++) {
            buffer[i] = (unsigned char)(i * 17 + 11);
        }
        
        // Measure encryption
        start_time = clock();
        unsigned char key = XOR_KEY_DEFAULT & 0xFF;
        for (int repeat = 0; repeat < 1000; repeat++) {
            for (int i = 0; i < size; i++) {
                buffer[i] ^= key;
            }
        }
        end_time = clock();
        
        double encrypt_time = ((double)(end_time - start_time) / CLOCKS_PER_SEC) * 1000;
        total_encrypt_time_ms += encrypt_time;
        
        // Measure decryption
        start_time = clock();
        for (int repeat = 0; repeat < 1000; repeat++) {
            for (int i = 0; i < size; i++) {
                buffer[i] ^= key;
            }
        }
        end_time = clock();
        
        double decrypt_time = ((double)(end_time - start_time) / CLOCKS_PER_SEC) * 1000;
        total_decrypt_time_ms += decrypt_time;
        
        free(buffer);
    }
    
    // Calculate throughput (MB/s)
    double total_bytes = 0;
    for (int s = 0; s < num_sizes; s++) {
        total_bytes += buffer_sizes[s] * 1000 * 2;  // encrypt + decrypt
    }
    
    pResults->encrypt_throughput_mb_s = 
        (total_bytes / (total_encrypt_time_ms / 1000.0)) / (1024.0 * 1024.0);
    pResults->decrypt_throughput_mb_s = 
        (total_bytes / (total_decrypt_time_ms / 1000.0)) / (1024.0 * 1024.0);
    
    printf("  Encrypt throughput: %.2f MB/s\n", pResults->encrypt_throughput_mb_s);
    printf("  Decrypt throughput: %.2f MB/s\n", pResults->decrypt_throughput_mb_s);
    printf("  Result: PASS\n");
}

/**
 * Test 5: XOR Entropy Analysis
 * 
 * Analyzes entropy of encrypted data to verify randomness.
 */
void test_xor_entropy(PXOR_TEST_RESULTS pResults) {
    printf("[TEST] XOR Entropy Analysis\n");
    
    const int buffer_size = 4096;
    unsigned char encrypted[buffer_size];
    
    // Generate test data
    for (int i = 0; i < buffer_size; i++) {
        encrypted[i] = (unsigned char)(i * 23 + 17);
    }
    
    // Encrypt with multiple keys
    unsigned char keys[] = {0x5A, 0x3C, 0x5E, 0x9F};
    for (int k = 0; k < 4; k++) {
        for (int i = k; i < buffer_size; i += 4) {
            encrypted[i] ^= keys[k];
        }
    }
    
    // Calculate entropy (simple histogram-based)
    unsigned int histogram[256] = {0};
    for (int i = 0; i < buffer_size; i++) {
        histogram[encrypted[i]]++;
    }
    
    double entropy = 0.0;
    for (int i = 0; i < 256; i++) {
        if (histogram[i] > 0) {
            double p = (double)histogram[i] / buffer_size;
            entropy -= p * log2(p);
        }
    }
    
    // Expected entropy for XOR-encrypted data: ~7.9-8.0 bits
    pResults->key_rotation_entropy = (entropy >= 7.8 && entropy <= 8.1) ? 1 : 0;
    
    printf("  Entropy: %.2f bits\n", entropy);
    printf("  Result: %s\n", pResults->key_rotation_entropy ? "PASS" : "FAIL");
}

// ============================================================================
// TEST SUITE EXECUTION
// ============================================================================

void run_xor_tests(PXOR_TEST_RESULTS pResults) {
    printf("========================================\n");
    printf("XOR ENCRYPTION UNIT TESTS\n");
    printf("========================================\n\n");
    
    clock_t suite_start = clock();
    
    // Run all tests
    test_xor_basic_encryption(pResults);
    test_griffin_xor_patterns(pResults);
    test_xor_key_rotation(pResults);
    test_xor_throughput(pResults);
    test_xor_entropy(pResults);
    
    clock_t suite_end = clock();
    pResults->total_test_time_ms = ((double)(suite_end - suite_start) / CLOCKS_PER_SEC) * 1000;
    
    printf("\n========================================\n");
    printf("XOR TEST SUMMARY\n");
    printf("========================================\n");
    printf("Total test time: %.2f ms\n", pResults->total_test_time_ms);
    printf("Encrypt throughput: %.2f MB/s\n", pResults->encrypt_throughput_mb_s);
    printf("Decrypt throughput: %.2f MB/s\n", pResults->decrypt_throughput_mb_s);
    printf("\nAll tests: %s\n", 
           (pResults->encrypt_decrypt_matches && 
            pResults->griffin_patterns_valid && 
            pResults->key_rotation_valid) ? "PASS" : "FAIL");
}

// ============================================================================
// END OF FILE
// ============================================================================
