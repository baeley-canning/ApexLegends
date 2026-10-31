/**
 * Phase 2 Kernel Driver - XOR Encryption Implementation
 *
 * Griffin-compatible XOR encryption with key rotation and pattern support
 */

#include "phase2.h"

// ============================================================================
// XOR KEY CONSTANTS
// ============================================================================

#define XOR_KEY_DEFAULT       0x5A3C5E9F
#define XOR_KEY_ROTATION_MS   (30 * 1000)   // 30 seconds in ms
#define XOR_BLOCK_SIZE_BYTES  16            // 128-bit blocks

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Initialize XOR context with seed key
 */
NTSTATUS
Phase2XorInitialize(
    _Inout_ PXOR_CONTEXT pContext,
    _In_opt_ PUCHAR pSeedKey,
    _In_opt_ ULONG SeedKeyLen
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Initializing XOR context");
    
    // Initialize current key with default or seed
    if (pSeedKey && SeedKeyLen > 0) {
        RtlCopyMemory(pContext->CurrentKey.Key, pSeedKey,
                     min(SeedKeyLen, XOR_BLOCK_SIZE_BYTES));
    } else {
        // Default key: 0x5A3C5E9F pattern
        PUCHAR pDefaultKey = (PUCHAR)&XOR_KEY_DEFAULT;
        RtlCopyMemory(pContext->CurrentKey.Key, pDefaultKey, 4);
        // Fill remaining bytes with pattern
        for (int i = 4; i < XOR_BLOCK_SIZE_BYTES; i++) {
            pContext->CurrentKey.Key[i] = pDefaultKey[i % 4] ^ (UCHAR)i;
        }
    }
    
    // Initialize previous key as copy of current
    RtlCopyMemory(&pContext->PreviousKey, &pContext->CurrentKey, sizeof(XOR_KEY));
    
    // Reset counters
    pContext->CurrentKey.RotationCounter = 0;
    pContext->CurrentKey.LastRotationTime.QuadPart = 0;
    pContext->PreviousKey.RotationCounter = 0;
    pContext->PreviousKey.LastRotationTime.QuadPart = 0;
    
    pContext->KeyRotated = FALSE;
    pContext->EncryptedBytes = 0;
    pContext->DecryptedBytes = 0;
    
    PHASE2_TRACE("XOR context initialized with key: 0x%08X", 
                 *(PULONG)pContext->CurrentKey.Key);
    
    return Status;
}

/**
 * @brief Encrypt data using XOR cipher
 */
VOID
Phase2XorEncrypt(
    _Inout_ PXOR_CONTEXT pContext,
    _In_reads_bytes_(Length) PUCHAR pData,
    _In_ SIZE_T Length
)
{
    if (!pData || Length == 0) {
        return;
    }
    
    // Get current key bytes
    PUCHAR pKey = pContext->CurrentKey.Key;
    ULONG keyIndex = pContext->CurrentKey.RotationCounter % XOR_BLOCK_SIZE_BYTES;
    
    // Apply XOR encryption
    for (SIZE_T i = 0; i < Length; i++) {
        pData[i] ^= pKey[(keyIndex + i) % XOR_BLOCK_SIZE_BYTES];
    }
    
    // Update counters
    pContext->EncryptedBytes += (ULONG)Length;
    pContext->CurrentKey.RotationCounter += (ULONG)(Length / XOR_BLOCK_SIZE_BYTES);
}

/**
 * @brief Decrypt data using XOR cipher (symmetric operation)
 */
VOID
Phase2XorDecrypt(
    _Inout_ PXOR_CONTEXT pContext,
    _In_reads_bytes_(Length) PUCHAR pData,
    _In_ SIZE_T Length
)
{
    // XOR is symmetric - same operation for encrypt/decrypt
    Phase2XorEncrypt(pContext, pData, Length);
    
    // Update decrypted bytes counter
    pContext->DecryptedBytes += (ULONG)Length;
}

/**
 * @brief Rotate XOR key for long-term obfuscation
 */
NTSTATUS
Phase2XorRotateKey(
    _Inout_ PXOR_CONTEXT pContext
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Rotating XOR key");
    
    // Save current key as previous
    RtlCopyMemory(&pContext->PreviousKey, &pContext->CurrentKey, sizeof(XOR_KEY));
    
    // Generate new key based on rotation counter
    ULONG rotation = pContext->CurrentKey.RotationCounter;
    PUCHAR pKey = pContext->CurrentKey.Key;
    
    // Apply rotation pattern (similar to Griffin's 30s rotation)
    for (int i = 0; i < XOR_BLOCK_SIZE_BYTES; i++) {
        // XOR with rotation-based offset
        pKey[i] ^= (UCHAR)((rotation >> (i * 2)) & 0xFF);
        // Add pattern-based variation
        pKey[i] ^= (UCHAR)(i * 7 + 3);
    }
    
    // Update rotation timestamp
    pContext->CurrentKey.LastRotationTime = KeQueryPerformanceCounter(NULL);
    
    // Mark as rotated
    pContext->KeyRotated = TRUE;
    
    PHASE2_TRACE("XOR key rotated (counter=%d)", rotation);
    
    return Status;
}

/**
 * @brief Apply Griffin-compatible XOR pattern
 */
NTSTATUS
Phase2ApplyGriffinXorPattern(
    _Inout_ PUCHAR pData,
    _In_ SIZE_T Length,
    _In_ ULONG PatternId
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    // Griffin XOR patterns:
    // Pattern 1: 0x5A3C5E9F (primary)
    // Pattern 2: 0xF9E5C3A5 (rotated)
    // Pattern 3: 0xA5C3E5F9 (mirrored)
    
    const ULONG griffinPatterns[3] = {
        0x5A3C5E9F,  // Pattern 1
        0xF9E5C3A5,  // Pattern 2
        0xA5C3E5F9   // Pattern 3
    };
    
    if (PatternId >= 3) {
        PatternId = PatternId % 3;
    }
    
    ULONG pattern = griffinPatterns[PatternId];
    PUCHAR pPatternBytes = (PUCHAR)&pattern;
    
    // Apply pattern-based XOR
    for (SIZE_T i = 0; i < Length; i++) {
        pData[i] ^= pPatternBytes[i % 4];
    }
    
    PHASE2_TRACE("Applied Griffin XOR pattern %d (0x%08X)", PatternId, pattern);
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
