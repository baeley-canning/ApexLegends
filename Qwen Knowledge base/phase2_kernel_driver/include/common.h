/**
 * Phase 2 Kernel Driver - Common Header
 * 
 * Core type definitions, macros, and constants for Javelin evasion patterns
 */

#pragma once

#ifndef __PHASE2_COMMON_H__
#define __PHASE2_COMMON_H__

// ============================================================================
// INCLUDES
// ============================================================================

#include <ntddk.h>
#include <ntdef.h>
#include <wdf.h>
#include <windef.h>

// ============================================================================
// VERSION INFORMATION
// ============================================================================

#define PHASE2_DRIVER_VERSION_MAJOR   2
#define PHASE2_DRIVER_VERSION_MINOR   0
#define PHASE2_DRIVER_VERSION_BUILD   1
#define PHASE2_DRIVER_VERSION_REVISION 0

#define PHASE2_DRIVER_VERSION_STRING  "2.0.1.0"

// ============================================================================
// CONSTANTS
// ============================================================================

#define PHASE2_POOL_TAG               '2ZaP'  // Phase2
#define PHASE2_MAX_STR_LENGTH         256
#define PHASE2_MAX_PATH_LENGTH        512

// Detection category masks (7 categories from Javelin)
#define DETECTION_SIGNATURE           (1ULL << 0)
#define DETECTION_BEHAVIORAL          (1ULL << 1)
#define DETECTION_ML                  (1ULL << 2)
#define DETECTION_HEURISTIC           (1ULL << 3)
#define DETECTION_HARDWARE            (1ULL << 4)
#define DETECTION_KERNEL              (1ULL << 5)
#define DETECTION_SERVER              (1ULL << 6)

// ============================================================================
// MEMORY CONSTANTS
// ============================================================================

#define PAGE_SIZE                     0x1000
#define PAGE_SHIFT                    12

#define MEGABYTE                      (1024 * 1024)
#define GIGABYTE                      (1024 * 1024 * 1024)

// ============================================================================
// TIME CONSTANTS (for human baseline patterns)
// ============================================================================

#define ONE_MS                        10000ULL        // 1ms in 100ns units
#define ONE_SECOND                    (1000 * ONE_MS)

// Human reaction time: N(250ms, σ=75ms)
#define REACTION_TIME_MEAN_MS         250
#define REACTION_TIME_STDDEV_MS       75

// Micro-jitter: N(0, σ=1.5°) at 60Hz
#define MICRO_JITTER_STDDEV_DEG       1.5
#define MICRO_JITTER_FREQ_HZ          60
#define MICRO_JITTER_PERIOD_MS        (1000 / MICRO_JITTER_FREQ_HZ)

// Batch interval: N(60s, σ=5-10s)
#define BATCH_INTERVAL_MEAN_S         60
#define BATCH_INTERVAL_STDDEV_S       7

// ============================================================================
// XOR ENCRYPTION CONSTANTS
// ============================================================================

#define XOR_KEY_ROTATION_INTERVAL     (30 * ONE_SECOND)   // 30 minutes
#define XOR_BLOCK_SIZE                16                  // 128-bit blocks
#define XOR_IV_SIZE                   16

// ============================================================================
// Griffin VM CONSTANTS
// ============================================================================

#define GriffinSectionName            ".grfn"
#define GriffinSectionSize            0x1000
#define MAX_MBA_EXPRESSIONS           256
#define MAX_VM_CONTEXTS               64

// ============================================================================
// STATUS CODES
// ============================================================================

typedef enum _PHASE2_STATUS {
    PHASE2_STATUS_SUCCESS = 0,
    PHASE2_STATUS_INVALID_PARAMETER,
    PHASE2_STATUS_ALLOCATED_MEMORY,
    PHASE2_STATUS_HOOKED,
    PHASE2_STATUS_ENCRYPTED,
    PHASE2_STATUS_TIMEOUT,
    PHASE2_STATUS_NOT_FOUND,
    PHASE2_STATUS_ALREADY_REGISTERED,
    PHASE2_STATUS_ERROR
} PHASE2_STATUS, *PPHASE2_STATUS;

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

// Generic pointer type for cross-platform compatibility
typedef VOID* PVOID;
typedef CONST VOID* PCVOID;

// Boolean types
#ifndef BOOLEAN
typedef UCHAR BOOLEAN;
typedef BOOLEAN* PBOOLEAN;
#endif

#ifndef TRUE
#define TRUE    ((BOOLEAN)1)
#define FALSE   ((BOOLEAN)0)
#endif

// 64-bit integer for timestamps
typedef union _PHASE2_TIMESTAMP {
    ULONGLONG Value;
    struct {
        ULONG LowPart;
        ULONG HighPart;
    };
} PHASE2_TIMESTAMP, *PPHASE2_TIMESTAMP;

// ============================================================================
// MEMORY ALLOCATION MACROS
// ============================================================================

#define Phase2AllocatePool(Type, Size) \
    ExAllocatePool2((Type), (Size), PHASE2_POOL_TAG)

#define Phase2FreePool(Ptr) \
    ExFreePoolWithTag((Ptr), PHASE2_POOL_TAG)

#define Phase2AllocateZeroPool(Type, Size) \
    ExAllocatePool2((Type), (Size), PHASE2_POOL_TAG)

// ============================================================================
// DEBUG MACROS
// ============================================================================

#ifdef PHASE2_DEBUG
    #define PHASE2_TRACE(fmt, ...) \
        DbgPrint("[Phase2] " fmt "\n", ##__VA_ARGS__)
    
    #define PHASE2_ERROR(fmt, ...) \
        DbgPrint("[Phase2][ERROR] " fmt "\n", ##__VA_ARGS__)
    
    #define PHASE2_VERBOSE(fmt, ...) \
        DbgPrint("[Phase2][VERBOSE] " fmt "\n", ##__VA_ARGS__)
#else
    #define PHASE2_TRACE(fmt, ...)          ((void)0)
    #define PHASE2_ERROR(fmt, ...)          ((void)0)
    #define PHASE2_VERBOSE(fmt, ...)        ((void)0)
#endif

// ============================================================================
// BIT OPERATIONS
// ============================================================================

#define BIT(x)                      (1ULL << (x))
#define BITSET(x, b)                ((x) |= BIT(b))
#define BITCLEAR(x, b)              ((x) &= ~BIT(b))
#define BITTOGGLE(x, b)             ((x) ^= BIT(b))
#define BITREAD(x, b)               (((x) >> (b)) & 1)

// ============================================================================
// ALIGNMENT MACROS
// ============================================================================

#define ALIGN_DOWN(Value, Alignment) \
    ((Value) & ~((Alignment) - 1))

#define ALIGN_UP(Value, Alignment) \
    (((Value) + ((Alignment) - 1)) & ~((Alignment) - 1))

// ============================================================================
// STRING OPERATIONS
// ============================================================================

#define STRLEN(str)                 (RTL_NUMBER_OF(str) - 1)
#define STRCPY(dst, src)            RtlCopyMemory((dst), (src), STRLEN(src) + 1)

// ============================================================================
// ENDIANNESS
// ============================================================================

#if defined(_X86_) || defined(_AMD64_)
    #define PHASE2_LITTLE_ENDIAN
#endif

#ifdef PHASE2_LITTLE_ENDIAN
    #define PHASE2_CPU_IS_LITTLE_ENDIAN()   TRUE
#else
    #define PHASE2_CPU_IS_LITTLE_ENDIAN()   FALSE
#endif

// ============================================================================
// FUNCTION ATTRIBUTES
// ============================================================================

#define PHASE2_API                  __declspec(dllexport)
#define PHASE2_FASTCALL             __fastcall
#define PHASE2_NORETURN             __declspec(noreturn)
#define PHASE2_NAKED                __declspec(naked)

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __PHASE2_COMMON_H__
