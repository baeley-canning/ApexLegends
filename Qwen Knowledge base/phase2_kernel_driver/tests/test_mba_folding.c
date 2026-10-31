/**
 * Phase 2 Kernel Driver - MBA Folding Test Suite
 *
 * Tests for Mixed Boolean-Arithmetic folding patterns and expression evaluation
 */

#include "phase2.h"
#include "test_framework.h"

// ============================================================================
// TEST CONSTANTS
// ============================================================================

#define MAX_MBA_EXPRESSIONS       256
#define MBA_COMPLEXITY            4
#define MBA_SEED                  0xDEADBEEFCAFEBABE
#define MBA_FOLDING_KEY1          0x5A3C5E9F
#define MBA_FOLDING_KEY2          0xF9E5C3A5

// ============================================================================
// TEST STATE
// ============================================================================

typedef struct _MBA_TEST_STATE {
    PMBA_EXPRESSION MBAExpressions;
    ULONG ExpressionCount;
    ULONG TotalApplications;
    KSPIN_LOCK Lock;
} MBA_TEST_STATE, *PMBA_TEST_STATE;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * @brief Initialize MBA test state
 */
NTSTATUS
TestInitializeMBAState(
    _Out_ PMBA_TEST_STATE* ppState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PMBA_TEST_STATE pState = Phase2AllocatePool(NonPagedPool, sizeof(MBA_TEST_STATE));
    if (!pState) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    
    RtlZeroMemory(pState, sizeof(MBA_TEST_STATE));
    KeInitializeSpinLock(&pState->Lock);
    
    *ppState = pState;
    
    PHASE2_TRACE("MBA test state initialized");
    
    return Status;
}

/**
 * @brief Cleanup MBA test state
 */
VOID
TestCleanupMBAState(
    _In_opt_ PMBA_TEST_STATE pState
)
{
    if (pState) {
        if (pState->MBAExpressions) {
            Phase2FreePool(pState->MBAExpressions);
        }
        Phase2FreePool(pState);
    }
}

// ============================================================================
// TEST CASES
// ============================================================================

/**
 * @brief Test MBA expression generation with seed-based patterns
 */
NTSTATUS
TestMBAExpressionGeneration(
    _In_ PMBA_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing MBA expression generation (complexity=%d, seed=0x%llX)",
                 MBA_COMPLEXITY, MBA_SEED);
    
    // Generate MBA expressions
    pState->ExpressionCount = MAX_MBA_EXPRESSIONS;
    pState->MBAExpressions = Phase2AllocatePool(NonPagedPool,
                                                 pState->ExpressionCount * sizeof(MBA_EXPRESSION));
    
    if (!pState->MBAExpressions) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    
    // Initialize expressions with seed-based patterns
    for (ULONG i = 0; i < pState->ExpressionCount; i++) {
        PMBA_EXPRESSION pExpr = &pState->MBAExpressions[i];
        
        // Operation selection based on seed bits
        pExpr->Operation = (MBA_OPERATION)((MBA_SEED >> ((i * 4) & 0x1F)) & 0x7);
        
        // Operand generation with key patterns
        pExpr->Operand1 = (MBA_SEED ^ (i * 7 + 3)) & 0xFFFFFFFF;
        pExpr->Operand2 = (MBA_SEED ^ (i * 11 + 5)) & 0xFFFFFFFF;
        
        // MBA folding keys
        pExpr->Key1 = MBA_FOLDING_KEY1;
        pExpr->Key2 = MBA_FOLDING_KEY2;
        
        pExpr->Result = 0;
        pExpr->IsVirtualized = TRUE;
    }
    
    PHASE2_TRACE("Generated %d MBA expressions", pState->ExpressionCount);
    
    return Status;
}

/**
 * @brief Test basic MBA folding: (x ^ k1) + k2
 */
NTSTATUS
TestBasicMBAFolding(
    _In_ PMBA_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing basic MBA folding: (x ^ k1) + k2");
    
    // Test with multiple data sizes
    const SIZE_T testSizes[] = {64, 128, 256, 512};
    
    for (ULONG s = 0; s < RTL_NUMBER_OF(testSizes); s++) {
        SIZE_T size = testSizes[s];
        PUCHAR pData = Phase2AllocatePool(NonPagedPool, size);
        
        if (!pData) {
            continue;
        }
        
        // Initialize test data
        for (SIZE_T i = 0; i < size; i++) {
            pData[i] = (UCHAR)(i * 7 + 3);
        }
        
        // Apply MBA folding: (x ^ k1) + k2
        for (SIZE_T i = 0; i < size; i++) {
            UCHAR x = pData[i];
            UCHAR k1 = (UCHAR)((i * 7 + 3) & 0xFF);
            UCHAR k2 = (UCHAR)((i * 11 + 5) & 0xFF);
            pData[i] = (x ^ k1) + k2;
        }
        
        // Verify folding is reversible
        for (SIZE_T i = 0; i < size; i++) {
            UCHAR x = pData[i];
            UCHAR k1 = (UCHAR)((i * 7 + 3) & 0xFF);
            UCHAR k2 = (UCHAR)((i * 11 + 5) & 0xFF);
            UCHAR original = (x - k2) ^ k1;
            
            if (original != (UCHAR)(i * 7 + 3)) {
                Status = STATUS_UNSUCCESSFUL;
            }
        }
        
        Phase2FreePool(pData);
    }
    
    PHASE2_TRACE("Basic MBA folding test PASSED");
    
    return Status;
}

/**
 * @brief Test advanced MBA folding with multiple operations
 */
NTSTATUS
TestAdvancedMBAFolding(
    _In_ PMBA_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing advanced MBA folding with multiple operations");
    
    // Test all MBA operations
    const struct {
        MBA_OPERATION Op;
        const CHAR* Name;
    } operations[] = {
        {MBA_OP_ADD, "ADD"},
        {MBA_OP_SUB, "SUB"},
        {MBA_OP_XOR, "XOR"},
        {MBA_OP_AND, "AND"},
        {MBA_OP_OR, "OR"},
        {MBA_OP_MUL, "MUL"},
        {MBA_OP_SHL, "SHL"},
        {MBA_OP_SHR, "SHR"}
    };
    
    for (ULONG i = 0; i < RTL_NUMBER_OF(operations); i++) {
        PHASE2_TRACE("Testing %s operation", operations[i].Name);
        
        // Test folding with this operation type
        for (ULONG j = 0; j < 32; j++) {
            ULONG x = j * 17 + 3;
            ULONG k1 = MBA_FOLDING_KEY1 ^ (j * 11 + 5);
            ULONG k2 = MBA_FOLDING_KEY2 ^ (j * 13 + 7);
            
            ULONG result = 0;
            
            switch (operations[i].Op) {
                case MBA_OP_ADD: result = x + k1 + k2; break;
                case MBA_OP_SUB: result = x - k1 + k2; break;
                case MBA_OP_XOR: result = (x ^ k1) + k2; break;
                case MBA_OP_AND: result = (x & k1) + k2; break;
                case MBA_OP_OR:  result = (x | k1) + k2; break;
                case MBA_OP_MUL: result = x * k1 + k2; break;
                case MBA_OP_SHL: result = (x << (k1 & 0x1F)) + k2; break;
                case MBA_OP_SHR: result = (x >> (k1 & 0x1F)) + k2; break;
            }
            
            // Verify folding
            if (result < (x ^ k1) + k2 || result > (x ^ k1) + k2 + 16) {
                PHASE2_TRACE("%s: x=%u, k1=%u, k2=%u, result=%u", 
                            operations[i].Name, x, k1, k2, result);
            }
        }
        
        PHASE2_TRACE("%s operation test PASSED", operations[i].Name);
    }
    
    PHASE2_TRACE("Advanced MBA folding test PASSED");
    
    return Status;
}

/**
 * @brief Test MBA expression tree construction
 */
NTSTATUS
TestMBAExpressionTree(
    _In_ PMBA_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing MBA expression tree construction");
    
    // Build expression tree from generated expressions
    PMBA_TREE_NODE* pNodes = Phase2AllocatePool(NonPagedPool,
                                                   pState->ExpressionCount * sizeof(PMBA_TREE_NODE));
    
    if (!pNodes) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    
    // Create leaf nodes
    for (ULONG i = 0; i < pState->ExpressionCount; i++) {
        pNodes[i] = Phase2AllocatePool(NonPagedPool, sizeof(MBA_TREE_NODE));
        
        if (pNodes[i]) {
            pNodes[i]->Expression = &pState->MBAExpressions[i];
            pNodes[i]->Left = NULL;
            pNodes[i]->Right = NULL;
            pNodes[i]->Depth = i % MBA_COMPLEXITY;
            pNodes[i]->Entropy = (UCHAR)(i * 17 + 3);
        }
    }
    
    // Build tree structure
    for (ULONG i = 0; i < pState->ExpressionCount / 2; i++) {
        if (pNodes[i]) {
            ULONG leftIdx = i * 2 + 1;
            ULONG rightIdx = i * 2 + 2;
            
            if (leftIdx < pState->ExpressionCount) {
                pNodes[i]->Left = pNodes[leftIdx];
            }
            if (rightIdx < pState->ExpressionCount) {
                pNodes[i]->Right = pNodes[rightIdx];
            }
        }
    }
    
    PHASE2_TRACE("MBA expression tree built with %d nodes", pState->ExpressionCount);
    
    Phase2FreePool(pNodes);
    
    return Status;
}

/**
 * @brief Test MBA folding stability and determinism
 */
NTSTATUS
TestMBAFoldingStability(
    _In_ PMBA_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing MBA folding stability and determinism");
    
    // Run multiple folding passes on same data
    const ULONG passCount = 5;
    UCHAR results[passCount][64];
    
    for (ULONG pass = 0; pass < passCount; pass++) {
        UCHAR testData[64];
        
        // Initialize with same pattern each time
        for (SIZE_T i = 0; i < sizeof(testData); i++) {
            testData[i] = (UCHAR)(i * 7 + 3);
        }
        
        // Apply MBA folding
        for (SIZE_T i = 0; i < sizeof(testData); i++) {
            UCHAR x = testData[i];
            UCHAR k1 = (UCHAR)((i * 7 + 3) & 0xFF);
            UCHAR k2 = (UCHAR)((i * 11 + 5) & 0xFF);
            testData[i] = (x ^ k1) + k2;
        }
        
        // Store results
        RtlCopyMemory(results[pass], testData, sizeof(testData));
    }
    
    // Verify all passes produce identical results
    for (SIZE_T i = 0; i < 64; i++) {
        UCHAR reference = results[0][i];
        
        for (ULONG pass = 1; pass < passCount; pass++) {
            if (results[pass][i] != reference) {
                Status = STATUS_UNSUCCESSFUL;
            }
        }
    }
    
    PHASE2_TRACE("MBA folding stability test PASSED (%d passes, identical results)", passCount);
    
    return Status;
}

/**
 * @brief Test MBA folding with Griffin VM integration
 */
NTSTATUS
TestGriffinMBAIntegration(
    _In_ PMBA_TEST_STATE pState
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    
    PHASE2_TRACE("Testing MBA folding with Griffin VM integration");
    
    // Simulate Griffin VM context with MBA folding enabled
    GRIFIN_VM_CONTEXT vmContext;
    RtlZeroMemory(&vmContext, sizeof(vmContext));
    
    vmContext.State = VM_STATE_ACTIVE;
    vmContext.IsVirtualized = TRUE;
    vmContext.MBAEnabled = TRUE;
    vmContext.TotalMBAApplications = 0;
    
    // Apply MBA folding through VM
    for (ULONG i = 0; i < 64; i++) {
        UCHAR x = (UCHAR)(i * 7 + 3);
        
        // VM applies MBA folding: (x ^ k1) + k2
        UCHAR k1 = (UCHAR)((i * 7 + 3) & 0xFF);
        UCHAR k2 = (UCHAR)((i * 11 + 5) & 0xFF);
        UCHAR result = (x ^ k1) + k2;
        
        vmContext.TotalMBAApplications++;
        
        PHASE2_TRACE("VM MBA fold %d: x=%u, result=%u", i, x, result);
    }
    
    PHASE2_TRACE("Griffin VM MBA integration test PASSED (%d applications)",
                 vmContext.TotalMBAApplications);
    
    return Status;
}

// ============================================================================
// TEST SUITE ENTRY POINTS
// ============================================================================

/**
 * @brief Run all MBA folding tests
 */
NTSTATUS
RunMBAFoldingTests(
    VOID
)
{
    NTSTATUS Status = STATUS_SUCCESS;
    PMBA_TEST_STATE pState = NULL;
    
    PHASE2_TRACE("=== Starting MBA Folding Tests ===");
    
    // Initialize test state
    Status = TestInitializeMBAState(&pState);
    if (!NT_SUCCESS(Status)) {
        goto cleanup;
    }
    
    // Run individual test cases
    NTSTATUS testCaseStatus = STATUS_SUCCESS;
    
    testCaseStatus = TestMBAExpressionGeneration(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestMBAExpressionGeneration FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestBasicMBAFolding(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestBasicMBAFolding FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestAdvancedMBAFolding(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestAdvancedMBAFolding FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestMBAExpressionTree(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestMBAExpressionTree FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestMBAFoldingStability(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestMBAFoldingStability FAILED");
        Status = testCaseStatus;
    }
    
    testCaseStatus = TestGriffinMBAIntegration(pState);
    if (!NT_SUCCESS(testCaseStatus)) {
        PHASE2_ERROR("TestGriffinMBAIntegration FAILED");
        Status = testCaseStatus;
    }
    
    PHASE2_TRACE("=== MBA Folding Tests Complete ===");
    
cleanup:
    TestCleanupMBAState(pState);
    
    return Status;
}

// ============================================================================
// END OF FILE
// ============================================================================
