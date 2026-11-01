#pragma once

// Shared ABI header: included by the user-mode launcher AND by the WDM driver.
// In user mode the Win32 types come from <windows.h>.  Inside the driver they
// are already provided by ntddk.h/ntifs.h - and pulling windows.h into a kernel
// TU drags the user-mode API declarations (synchapi.h, processthreadsapi.h) into
// a context where they do not parse (C2059 storm).  The macros below are the
// WDK's own include guards, so they are set exactly when ntddk.h/ntifs.h/wdm.h
// have been seen; CTL_CODE, DWORD, ULONG etc. are all available by then.

// ============================================================================
// Shared ABI between apex_launcher.exe and the companion driver apexdrv.sys.
// Both sides MUST agree on these values; keep this header as the single
// source of truth (the driver includes it too).
// ============================================================================

#define APEXDRV_SERVICE_NAME    L"apexdrv"
#define APEXDRV_DEVICE_NAME     L"\\Device\\ApexDrv"
#define APEXDRV_SYMLINK_NAME    L"\\DosDevices\\ApexDrv"
#define APEXDRV_WIN32_NAME      L"\\\\.\\ApexDrv"

// Device type chosen outside the ranges Microsoft uses for its own drivers.
#define APEXDRV_DEVICE_TYPE    0x8A70

// CTL_CODE() expands to an `int` expression: APEXDRV_DEVICE_TYPE << 16 is
// 0x8A700000, which does not fit in a signed int (C4245 when passed as a DWORD
// parameter, fatal under /WX).  The cast pins the macro to ULONG's bit pattern
// and keeps both sides of the ABI (launcher + driver) identical.  A C-style
// cast, not static_cast: apexdrv.c is compiled as C and includes this header.
#define IOCTL_APEXDRV_INJECT \
    ((ULONG)CTL_CODE(APEXDRV_DEVICE_TYPE, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS))

#define IOCTL_APEXDRV_VERSION \
    ((ULONG)CTL_CODE(APEXDRV_DEVICE_TYPE, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS))

// Kernel-context reachability probe (question Q10 in the PHASE 1 measurement
// record).  User mode is refused on the live target even elevated - OpenProcess
// succeeds, but VirtualAllocEx/NtAllocateVirtualMemory/NtCreateThreadEx and even
// ReadProcessMemory fail.  This IOCTL repeats the *same* three steps from kernel
// context (open with injector rights -> allocate/write/release -> copy the target
// PEB out) and returns the NTSTATUS of EVERY step separately, so the layer that
// owns the denial is identified instead of guessed.  The IOCTL itself returns
// STATUS_SUCCESS whenever the request was understood: a failing step is data.
#define IOCTL_APEXDRV_PROBE \
    ((ULONG)CTL_CODE(APEXDRV_DEVICE_TYPE, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS))

// Flags for APEXDRV_INJECT_REQUEST::Flags
#define APEXDRV_FLAG_NONE       0x00000000
#define APEXDRV_FLAG_APC_ONLY   0x00000001  // queue an APC instead of creating a thread

#define APEXDRV_MAX_PATH_CHARS  260
// 2 = added IOCTL_APEXDRV_PROBE (Q10).  A driver older than the launcher simply
//     fails the probe IOCTL instead of misreading a length.
#define APEXDRV_VERSION         2

// Bytes of the target PEB copied out for inspection.  The PEB's first fields
// (ImageBaseAddress at +0x10 on x64, Ldr at +0x18) are what the user-mode
// reader needs and cannot get, and they sit inside the first 32 bytes.
#define APEXDRV_PROBE_BYTES     32

// PACKING: this header is included after <ntddk.h>/<ntifs.h> in the driver TU, which
// brings in the WDM headers' #pragma pack(4); the user-mode TU (apex_launcher / the
// PowerShell probes) gets the default pack(8).  Without this pin,
// sizeof(APEXDRV_PROBE_REQUEST) is 84 in the driver and 88 in user mode, so the two
// ULONG64 trailer fields land 4 bytes apart and user mode reads a garbage PEB address.
// pack(1) is chosen because it reproduces EXACTLY the layout of the already-deployed
// driver (84 bytes; PebAddress at 36, RemoteAllocation at 44, Bytes at 52), so the fix
// needs no driver re-flash.  APEXDRV_INJECT_REQUEST is pack-insensitive (552 either way).
#pragma pack(push, 1)

typedef struct _APEXDRV_INJECT_REQUEST {
    ULONG   ProcessId;                          // [in]
    ULONG   Flags;                              // [in]  APEXDRV_FLAG_*
    ULONG64 LoadLibraryAddress;                 // [in]  address of kernel32!LoadLibraryW
                                                //       valid inside the target process
                                                //       (same build => same export RVA)
    WCHAR   DllPath[APEXDRV_MAX_PATH_CHARS];    // [in]  full path of apexcheat.dll
    LONG    ResultStatus;                       // [out] NTSTATUS of the operation
    ULONG   ThreadId;                           // [out]
    ULONG64 RemoteBase;                         // [out] remote path buffer address
} APEXDRV_INJECT_REQUEST, *PAPEXDRV_INJECT_REQUEST;

typedef struct _APEXDRV_VERSION_INFO {
    ULONG Version;
    ULONG Reserved;
} APEXDRV_VERSION_INFO, *PAPEXDRV_VERSION_INFO;

// One request/response for IOCTL_APEXDRV_PROBE.  Every Status* field carries an
// NTSTATUS value typed as LONG so the header stays valid in user mode, where
// NTSTATUS is not defined.  Statuses are reported, never aggregated: the whole
// point is to learn WHICH step the anti-cheat refuses.
typedef struct _APEXDRV_PROBE_REQUEST {
    ULONG   ProcessId;                      // [in]
    ULONG   Flags;                          // [in] reserved, 0
    LONG    StatusLookup;                   // [out] PsLookupProcessByProcessId
    LONG    StatusOpen;                     // [out] ObOpenObjectByPointer(full rights)
    LONG    StatusAllocate;                 // [out] ZwAllocateVirtualMemory (target)
    LONG    StatusWrite;                    // [out] ApexdrvWriteProcessMemory (target) -
                                                //   KeStackAttachProcess + RtlCopyMemory, not ZwWriteVirtualMemory
    LONG    StatusFree;                     // [out] ZwFreeVirtualMemory (target)
    LONG    StatusCopyVirtual;              // [out] MmCopyVirtualMemory (target -> us)
    ULONG   BytesCopied;                    // [out] bytes actually copied out
    ULONG64 PebAddress;                     // [out] EPROCESS->Peb (0 when none)
    ULONG64 RemoteAllocation;               // [out] address the allocation landed at
    UCHAR   Bytes[APEXDRV_PROBE_BYTES];     // [out] leading bytes of the target PEB
} APEXDRV_PROBE_REQUEST, *PAPEXDRV_PROBE_REQUEST;

#pragma pack(pop)   // see the packing note above the structs

