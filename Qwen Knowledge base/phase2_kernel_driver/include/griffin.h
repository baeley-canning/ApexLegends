/**
 * Phase 2 Kernel Driver - Griffin VM Integration Header
 * 
 * Griffin VM integration with .grfn sections, MBA folding, and INT3 resolution
 */

#pragma once

#ifndef __PHASE2_GRIFFIN_H__
#define __PHASE2_GRIFFIN_H__

#include "common.h"
#include "obfuscation.h"

// ============================================================================
// GRIFIN SECTION CONSTANTS
// ============================================================================

#define GRIFIN_SECTION_NAME           ".grfn"
#define GRIFIN_SECTION_SIZE           0x1000
#define GRIFIN_SECTION_ALIGNMENT      0x1000

// Griffin VM context structure layout
#define GRIFIN_VM_CONTEXT_OFFSET      0x0000
#define GRIFIN_MBA_CONFIG_OFFSET      0x0100
#define GRIFIN_INT3_CONFIG_OFFSET     0x0200
#define GRIFIN_TELEMETRY_CONFIG_OFFSET 0x0300

// ============================================================================
// GRIFIN VM REGISTERS
// ============================================================================

typedef enum _GRIFIN_VM_REGISTER {
    VM_REG_RAX = 0,
    VM_REG_RCX,
    VM_REG_RDX,
    VM_REG_RBX,
    VM_REG_RSP,
    VM_REG_RBP,
    VM_REG_RSI,
    VM_REG_RDI,
    VM_REG_R8,
    VM_REG_R9,
    VM_REG_R10,
    VM_REG_R11,
    VM_REG_R12,
    VM_REG_R13,
    VM_REG_R14,
    VM_REG_R15,
    VM_REG_RIP,
    VM_REG_RFLAGS,
    VM_REG_MAX
} GRIFIN_VM_REGISTER;

// ============================================================================
// GRIFIN VM STATE
// ============================================================================

typedef enum _GRIFIN_VM_STATE {
    VM_STATE_IDLE = 0,
    VM_STATE_VIRTUALIZING,
    VM_STATE_EXECUTING,
    VM_STATE_RESOLVING_INT3,
    VM_STATE_APPLYING_MBA,
    VM_STATE_MAX
} GRIFIN_VM_STATE;

// ============================================================================
// MBA EXPRESSION STRUCTURES
// ============================================================================

typedef enum _MBA_OPERATION {
    MBA_OP_ADD = 0,
    MBA_OP_SUB,
    MBA_OP_XOR,
    MBA_OP_AND,
    MBA_OP_OR,
    MBA_OP_MUL,
    MBA_OP_SHL,
    MBA_OP_SHR,
    MBA_OP_MAX
} MBA_OPERATION;

typedef struct _MBA_EXPRESSION {
    ULONG Operation;
    ULONG64 Operand1;
    ULONG64 Operand2;
    ULONG64 Result;
    BOOLEAN IsVirtualized;
} MBA_EXPRESSION, *PMBA_EXPRESSION;

typedef struct _MBA_TREE_NODE {
    PMBA_EXPRESSION Expression;
    struct _MBA_TREE_NODE* Left;
    struct _MBA_TREE_NODE* Right;
    ULONG Depth;
    ULONG Entropy;
} MBA_TREE_NODE, *PMBA_TREE_NODE;

// ============================================================================
// INT3 BREAKPOINT STRUCTURES
// ============================================================================

typedef enum _INT3_RESOLUTION_STRATEGY {
    INT3_STRATEGY_LINEAR = 0,
    INT3_STRATEGY_POLYNOMIAL,
    INT3_STRATEGY_EXPONENTIAL,
    INT3_STRATEGY_MAX
} INT3_RESOLUTION_STRATEGY;

typedef struct _INT3_BREAKPOINT {
    PVOID Address;
    UCHAR OriginalByte;
    BOOLEAN IsResolved;
    ULONG ResolutionAttempts;
    LARGE_INTEGER FirstDetectedTime;
    LARGE_INTEGER LastResolveTime;
} INT3_BREAKPOINT, *PINT3_BREAKPOINT;

// ============================================================================
// GRIFIN VM CONTEXT STRUCTURE
// ============================================================================

typedef struct _GRIFIN_VM_CONTEXT {
    // Virtual registers (RAX-R15, RIP, RFLAGS)
    ULONG64 VirtualRegisters[VM_REG_MAX];
    
    // VM state
    GRIFIN_VM_STATE State;
    BOOLEAN IsVirtualized;
    BOOLEAN MBAEnabled;
    BOOLEAN INT3Enabled;
    
    // Configuration
    ULONG MBAExpressionCount;
    ULONG MBAComplexity;
    ULONG INT3Strategy;
    ULONG TimeoutMs;
    
    // Statistics
    ULONG TotalInstructionsExecuted;
    ULONG TotalMBAApplications;
    ULONG TotalINT3Resolutions;
    LARGE_INTEGER TotalVirtualizationTime;
} GRIFIN_VM_CONTEXT, *PGRIFIN_VM_CONTEXT;

// ============================================================================
// GRIFIN OBFUSCATION CONFIGURATION
// ============================================================================

typedef struct _GRIFIN_OBFUSCATION_CONFIG {
    // Section configuration
    BOOLEAN EnableGriffinSections;
    PUCHAR SectionData;
    SIZE_T SectionSize;
    
    // MBA folding configuration
    BOOLEAN EnableMBAFolding;
    PMBA_EXPRESSION MBAExpressions;
    ULONG MBAExpressionCount;
    ULONG MaxMBAComplexity;
    ULONG64 MBASeed;
    
    // INT3 resolution configuration
    BOOLEAN EnableINT3Resolution;
    PINT3_BREAKPOINT INT3Breakpoints;
    ULONG INT3BreakpointCount;
    INT3_RESOLUTION_STRATEGY INT3Strategy;
    ULONG INT3TimeoutMs;
    
    // Telemetry configuration
    BOOLEAN EnableTelemetryObfuscation;
    ULONG TelemetryBatchIntervalMs;
} GRIFIN_OBFUSCATION_CONFIG, *PGRIFIN_OBFUSCATION_CONFIG;

// ============================================================================
// FUNCTION PROTOTYPES - GRIFIN SECTION MANAGEMENT
// ============================================================================

NTSTATUS
GriffinCreateSection(
    _Inout_ PUCHAR* ppSectionData,
    _Out_ PSIZE_T pSectionSize
);

NTSTATUS
GriffinWriteContextToSection(
    _In_ PUCHAR pSectionData,
    _In_ PGRIFIN_VM_CONTEXT pVmContext
);

NTSTATUS
GriffinReadContextFromSection(
    _In_ PUCHAR pSectionData,
    _Out_ PGRIFIN_VM_CONTEXT pVmContext
);

// ============================================================================
// FUNCTION PROTOTYPES - MBA FOLDING
// ============================================================================

NTSTATUS
GriffinInitializeMBAExpressions(
    _Out_ PMBA_EXPRESSION* ppExpressions,
    _In_ ULONG ExpressionCount,
    _In_ ULONG Complexity,
    _In_ ULONG64 Seed
);

VOID
GriffinApplyMBAExpression(
    _Inout_ PMBA_EXPRESSION pExpression,
    _In_ BOOLEAN ApplyFolding
);

NTSTATUS
GriffinBuildMBAExpressionTree(
    _In_reads_bytes_(Size) PUCHAR pData,
    _In_ SIZE_T Size,
    _In_ PMBA_EXPRESSION pExpressions,
    _In_ ULONG ExpressionCount,
    _Out_ PMBA_TREE_NODE* ppRootNode
);

VOID
GriffinFoldMBAExpression(
    _Inout_ PMBA_EXPRESSION pExpression
);

// ============================================================================
// FUNCTION PROTOTYPES - INT3 RESOLUTION
// ============================================================================

NTSTATUS
GriffinRegisterINT3Breakpoint(
    _Inout_ PINT3_BREAKPOINT* ppBreakpoints,
    _In_ ULONG_PTR Address,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
);

NTSTATUS
GriffinResolveINT3Breakpoint(
    _Inout_ PINT3_BREAKPOINT pBreakpoint,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
);

NTSTATUS
GriffinResolveAllINT3Breakpoints(
    _Inout_ PINT3_BREAKPOINT pBreakpoints,
    _In_ ULONG BreakpointCount,
    _In_ PGRIFIN_OBFUSCATION_CONFIG pConfig
);

// ============================================================================
// FUNCTION PROTOTYPES - GRIFIN VM OPERATIONS
// ============================================================================

NTSTATUS
GriffinInitializeVMContext(
    _Out_ PGRIFIN_VM_CONTEXT* ppVmContext
);

VOID
GriffinCleanupVMContext(
    _In_opt_ PGRIFIN_VM_CONTEXT pVmContext
);

VOID
GriffinVirtualizeInstruction(
    _Inout_ PGRIFIN_VM_CONTEXT pVmContext,
    _In_ ULONG64 InstructionPointer
);

NTSTATUS
GriffinExecuteVirtualizedBlock(
    _Inout_ PGRIFIN_VM_CONTEXT pVmContext,
    _In_reads_bytes_(Size) PUCHAR pData,
    _In_ SIZE_T Size
);

// ============================================================================
// MACROS
// ============================================================================

#define GRIFIN_FLAG_VIRTUALIZED       BIT(0)
#define GRIFIN_FLAG_MBA_FOLDED        BIT(1)
#define GRIFIN_FLAG_INT3_RESOLVED     BIT(2)
#define GRIFIN_FLAG_TELEMETRY_OBFUSCATED BIT(3)

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __PHASE2_GRIFFIN_H__
