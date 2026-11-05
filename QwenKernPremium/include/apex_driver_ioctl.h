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

// Read-only diagnostics against one target process (no injection, no mutation):
// the loader-side facts the inject rung needs and user mode cannot obtain on the
// live game (RPM is refused there).  Fills in the kernel32/kernelbase bases, the
// module count, the *target-side* resolved address of kernel32!LoadLibraryW and
// the TEB LastErrorValue of a chosen thread.  Safe to run at any time.
#define IOCTL_APEXDRV_TARGETINFO \
    ((ULONG)CTL_CODE(APEXDRV_DEVICE_TYPE, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS))

// Flags for APEXDRV_INJECT_REQUEST::Flags
#define APEXDRV_FLAG_NONE       0x00000000
#define APEXDRV_FLAG_APC_ONLY   0x00000001  // queue an APC instead of creating a thread

// v4: resolve kernel32!LoadLibraryW INSIDE the target (PEB->Ldr walk + kernelbase
// export table) instead of trusting the address the launcher resolved in its own
// address space, and report what the call actually did (module count delta, the
// module that appeared, TEB LastErrorValue).  The premise "kernel32 is mapped at
// the same base in every process of the session" is now measured per run instead
// of assumed - see ResolvePath/BasesDiffer in APEXDRV_TARGETINFO_REQUEST.
#define APEXDRV_FLAG_RESOLVE_IN_TARGET  0x00000002

#define APEXDRV_MAX_PATH_CHARS  260
// Long enough for any real BaseDllName; the Ldr walk copies at most this much and
// always NUL-terminates, so a hostile/oversized name cannot overrun the report.
#define APEXDRV_MAX_MODULE_NAME_CHARS 64
// 2 = added IOCTL_APEXDRV_PROBE (Q10).  A driver older than the launcher simply
//     fails the probe IOCTL instead of misreading a length.
// 3 = inject rung switched from ZwCreateThreadEx (NOT an export of ntoskrnl on
//     26100, MmGetSystemRoutineAddress returns NULL -> STATUS_PROC_NOT_FOUND) to
//     a user-mode APC queued on a caller-supplied thread.  The request grew the
//     ThreadId field; a v2 driver reads a v3 request only if the launcher checks
//     this value first, which it does.
// 4 = added IOCTL_APEXDRV_TARGETINFO plus the inject result fields (module count
//     before/after, the module that appeared, TEB LastErrorValue, ResolvePath,
//     BasesDiffer).  v4 is a diagnostic-only superset: a v4 launcher against a v3
//     driver is refused by the version check instead of reading past the struct.
// 5 = path proof.  h275 proved the resolved LoadLibraryW address is correct (the
//     target then fails with 87 = empty string, not 126 = missing file), so the
//     remaining question is whether the wide path really lands in the target.
//     RemotePathEcho/StatusEchoRead read the remote buffer back immediately after
//     the write, FiredSeen says whether the APC kernel routine ran at all, and the
//     *2 fields re-sample module count and LastError 1 s later so a late delivery
//     cannot be scored as a failure.
#define APEXDRV_VERSION         5

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
    ULONG   ThreadId;                           // [in]  existing thread of ProcessId the
                                                //       loader APC is queued on (v3: required -
                                                //       ZwCreateThreadEx is NOT an export on
                                                //       26100, see ApexdrvQueueLoaderApc);
                                                //       [out] the thread actually used
    ULONG64 LoadLibraryAddress;                 // [in]  address of kernel32!LoadLibraryW
                                                //       valid inside the target process
                                                //       (same build => same export RVA)
    WCHAR   DllPath[APEXDRV_MAX_PATH_CHARS];    // [in]  full path of apexcheat.dll
    LONG    ResultStatus;                       // [out] NTSTATUS of the operation
    ULONG64 RemoteBase;                         // [out] remote path buffer address
    // --- v4 result block: what the *user-mode* call did, not merely that it ran ---
    ULONG64 ResolvedLoadLibrary;                // [out] address actually used
    ULONG   ResolvePath;                        // [out] 0=caller-supplied 1=target export
    ULONG   BasesDiffer;                        // [out] 1 when the target's kernelbase base
                                                //       differs from the launcher's (premise test)
    ULONG   ModuleCountBefore;                  // [out] modules in the target before delivery
    ULONG   ModuleCountAfter;                   // [out] modules after the settle window
    ULONG64 NewModuleBase;                      // [out] DllBase of the module that appeared
    WCHAR   NewModuleName[APEXDRV_MAX_MODULE_NAME_CHARS]; // [out] its BaseDllName
    LONG    LoadLibraryLastError;               // [out] TEB LastErrorValue after delivery
    LONG    StatusReadResult;                   // [out] status of that read (data, not verdict)
    // --- v5: proof that the path string landed and that the APC ran at all ---
    ULONG   StatusEchoRead;                     // [out] status of the read-back itself, so a
                                                //       faulting read is not scored as "empty"
    WCHAR   RemotePathEcho[APEXDRV_MAX_PATH_CHARS]; // [out] remote buffer as read back right
                                                //       after the write: must equal DllPath
    ULONG   FiredSeen;                          // [out] 1 once the APC kernel routine ran;
                                                //       0 after the 3 s window means the thread
                                                //       never left kernel mode alertably
    ULONG   StatusEchoAfter;                    // [out] status of the post-delivery read-back
    WCHAR   RemotePathEchoAfter[APEXDRV_MAX_MODULE_NAME_CHARS]; // [out] echo 1 s later: proves
                                                //       the buffer was not clobbered or freed
    LONG    StatusReadResult2;                  // [out] status of the second LastError read
    LONG    LoadLibraryLastError2;              // [out] LastError 1 s later (late delivery)
    ULONG   ModuleCountAfter2;                  // [out] module count 1 s later
} APEXDRV_INJECT_REQUEST, *PAPEXDRV_INJECT_REQUEST;

typedef struct _APEXDRV_VERSION_INFO {
    ULONG Version;
    ULONG Reserved;
} APEXDRV_VERSION_INFO, *PAPEXDRV_VERSION_INFO;

// One request/response for IOCTL_APEXDRV_TARGETINFO (v4).  Read-only: nothing in
// the target is allocated, written or freed.
//
// Why it exists: the inject rung handed the driver an address resolved in the
// *launcher's* address space and the driver reported "delivered" without ever
// learning whether the call worked.  This IOCTL measures both halves:
//   * ResolvedLoadLibrary / KernelBaseBase  -> the address the target itself would
//     use, so a per-process base difference (or an address pointing at nothing)
//     stops being invisible;
//   * ModuleCount / LastErrorValue          -> the state that decides PASS/FAIL.
// BasesDiffer is filled by comparing against the *driver's own* process, so the
// comparison happens in one place and never depends on user-mode RPM.
typedef struct _APEXDRV_TARGETINFO_REQUEST {
    ULONG   ProcessId;                      // [in]
    ULONG   Flags;                          // [in] reserved, 0
    ULONG   ThreadId;                       // [in] optional: read this thread's
                                            //      LastErrorValue; 0 = skip
    LONG    StatusLookup;                   // [out] PsLookupProcessByProcessId
    LONG    StatusWalk;                     // [out] target PEB->Ldr walk
    LONG    StatusSelfWalk;                 // [out] the same walk on ourselves
    LONG    StatusResolve;                  // [out] kernelbase!LoadLibraryW lookup
    LONG    StatusReadResult;               // [out] TEB read below
    ULONG   ModuleCount;                    // [out] modules visible in the target
    ULONG   SelfModuleCount;                // [out] modules visible in us
    ULONG   BasesDiffer;                    // [out] 1 when the two kernelbase bases differ
    ULONG   LoadLibraryRva;                 // [out] RVA inside kernelbase (same build =>
                                            //       identical, so a mismatch is proof)
    ULONG64 Kernel32Base;                   // [out]
    ULONG64 KernelBaseBase;                 // [out]
    ULONG64 SelfKernel32Base;               // [out]
    ULONG64 SelfKernelBaseBase;             // [out]
    ULONG64 ResolvedLoadLibrary;            // [out] KernelBaseBase + LoadLibraryRva
    LONG    LastErrorValue;                 // [out] TEB+0x68 of ThreadId
} APEXDRV_TARGETINFO_REQUEST, *PAPEXDRV_TARGETINFO_REQUEST;

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

