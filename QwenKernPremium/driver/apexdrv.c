// ============================================================================
// apexdrv.sys — kernel half of the "KERNEL" injection strategy
//
// Contract with apex_launcher.exe lives in include/apex_driver_ioctl.h.
//
// IOCTL_APEXDRV_INJECT(ProcessId, LoadLibraryAddress, DllPath):
//   1. ZwOpenProcess(pid)              (kernel handle: no usermode OpenProcess
//                                        for the anti-cheat to observe)
//   2. ZwAllocateVirtualMemory in the target
//   3. ZwWriteVirtualMemory <- wide DLL path
//   4. ZwCreateThreadEx(start = LoadLibraryAddress, arg = remote path)
//   5. wait for the loader thread, release the path buffer, report thread id
//
// IOCTL_APEXDRV_PROBE(ProcessId) — kernel-context reachability probe (Q10):
//   lookup -> open with injector rights -> allocate/write/free -> copy the PEB
//   out, each step reporting its own NTSTATUS.  Answers "is B3 the only viable
//   path on this machine?" without depending on the user-mode handle at all.
//
// Build requirements
//   * WDK 10 + MSVC -> driver\apexdrv.vcxproj
//   * loadable by the standard loader: signed, test-signed
//     (bcdedit /set testsigning on), or pre-mapped via a BYOVD loader
//   * the launcher installs it as a demand-start SERVICE_KERNEL_DRIVER
// ============================================================================

#include <ntifs.h>
#include <ntddk.h>
#include <wdmsec.h>

#include "apex_driver_ioctl.h"

// ZwCreateThreadEx is neither declared by the WDK 10.0.26100 km headers nor
// present in ntoskrnl.lib (checked with dumpbin /linkermember:1 — no
// CreateThreadEx entry at all), even though ntoskrnl.exe exports it at runtime.
// So it is resolved once at first use through MmGetSystemRoutineAddress, which
// is the documented way to call an export the import library does not carry.
// Documented signature: 11 parameters.
typedef NTSTATUS (NTAPI *PFN_ZwCreateThreadEx)(
    PHANDLE            ThreadHandle,
    ACCESS_MASK        DesiredAccess,
    POBJECT_ATTRIBUTES ObjectAttributes,
    HANDLE             ProcessHandle,
    PVOID              StartRoutine,
    PVOID              Argument,
    ULONG              CreateFlags,
    SIZE_T             ZeroBits,
    SIZE_T             StackSize,
    SIZE_T             MaximumStackSize,
    PVOID              AttributeList);

// Same story as ZwCreateThreadEx: WDK 10.0.26100 declares neither of these in
// any header a WDM driver pulls in (verified by searching every .h under
// Include\10.0.26100.0), although both are documented, exported and stable.
// Declaring them here is what makes the kernel-side probe (Q10) portable across
// WDK revisions instead of relying on a header accident.
NTKERNELAPI PPEB NTAPI PsGetProcessPeb(PEPROCESS Process);

NTKERNELAPI NTSTATUS NTAPI MmCopyVirtualMemory(
    PEPROCESS        SourceProcess,
    PVOID            SourceAddress,
    PEPROCESS        TargetProcess,
    PVOID            TargetAddress,
    SIZE_T           BufferSize,
    KPROCESSOR_MODE  PreviousMode,
    PSIZE_T          ReturnSize);

// Same story for the write path: the 26100 import library carries neither
// ZwWriteVirtualMemory nor NtWriteVirtualMemory, and KeStackAttachProcess is
// available.  Entering the target's address space and copying is both simpler
// and more honest than a syscall that has to re-resolve the same CR3.
static NTSTATUS ApexdrvWriteProcessMemory(PEPROCESS process, PVOID baseAddress,
                                          const VOID* buffer, SIZE_T byteCount) {
    KAPC_STATE apcState;
    NTSTATUS   status = STATUS_SUCCESS;

    KeStackAttachProcess(process, &apcState);
    __try {
        RtlCopyMemory(baseAddress, buffer, byteCount);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
    }
    KeUnstackDetachProcess(&apcState);

    return status;
}

// v5 read-back.  The write path above only reports that the copy did not raise;
// it never showed the bytes.  This is the same trick in reverse so the caller can
// compare what the target actually holds against what was sent.
static NTSTATUS ApexdrvReadProcessMemory(PEPROCESS process, PVOID baseAddress,
                                         VOID* buffer, SIZE_T byteCount) {
    KAPC_STATE apcState;
    NTSTATUS   status = STATUS_SUCCESS;

    KeStackAttachProcess(process, &apcState);
    __try {
        RtlCopyMemory(buffer, baseAddress, byteCount);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
    }
    KeUnstackDetachProcess(&apcState);

    return status;
}

// The APC delivery pair used by the inject rung.  WDK 10.0.26100 declares
// neither the two functions nor the routine typedefs, nor KAPC_ENVIRONMENT /
// OriginalApcEnvironment, while ntoskrnl.lib DOES carry KeInitializeApc and
// KeInsertQueueApc - so the prototypes are pinned here exactly like the two
// above.  The typedefs are APEXDRV_-prefixed to stay clear of a kit that later
// starts declaring the documented names.
#define APEXDRV_TAG                 'vpxA'   // 'Apxv' (little-endian)

typedef VOID (NTAPI *APEXDRV_KNORMAL_ROUTINE)(PVOID NormalContext,
                                              PVOID SystemArgument1,
                                              PVOID SystemArgument2);

typedef VOID (NTAPI *APEXDRV_KKERNEL_ROUTINE)(PRKAPC Apc,
                                              APEXDRV_KNORMAL_ROUTINE* NormalRoutine,
                                              PVOID* NormalContext,
                                              PVOID* SystemArgument1,
                                              PVOID* SystemArgument2);

typedef VOID (NTAPI *APEXDRV_KRUNDOWN_ROUTINE)(PRKAPC Apc);

typedef enum _APEXDRV_KAPC_ENVIRONMENT {
    OriginalApcEnvironment,
    AttachedApcEnvironment,
    CurrentApcEnvironment,
    InsertApcEnvironment
} APEXDRV_KAPC_ENVIRONMENT;

NTKERNELAPI VOID NTAPI KeInitializeApc(PRKAPC Apc, PRKTHREAD Thread,
                                       APEXDRV_KAPC_ENVIRONMENT Environment,
                                       APEXDRV_KKERNEL_ROUTINE KernelRoutine,
                                       APEXDRV_KRUNDOWN_ROUTINE RundownRoutine,
                                       APEXDRV_KNORMAL_ROUTINE NormalRoutine,
                                       KPROCESSOR_MODE ApcMode,
                                       PVOID NormalContext);

NTKERNELAPI BOOLEAN NTAPI KeInsertQueueApc(PRKAPC Apc, PVOID SystemArgument1,
                                           PVOID SystemArgument2,
                                           KPRIORITY Increment);

// ----------------------------------------------------------------------------
// Loader delivery: user-mode APC on an existing thread.
//
// The obvious route - ZwCreateThreadEx resolved with MmGetSystemRoutineAddress -
// is DEAD on 26100: neither ZwCreateThreadEx nor ZwCreateThread nor
// NtCreateThread appears in ntoskrnl's export table (measured), so
// MmGetSystemRoutineAddress returns NULL and the ioctl used to fail with
// STATUS_PROCEDURE_NOT_FOUND, which user mode sees as GetLastError 127.
//
// What IS exported: PsLookupThreadByThreadId, KeInitializeApc, KeInsertQueueApc.
// A user-mode APC whose NormalRoutine is kernel32!LoadLibraryW delivers it with
// RCX = NormalContext, so passing the remote path as NormalContext is exactly
// the LoadLibraryW(path) call the thread-creation route made - without needing a
// syscall at all.  The APC fires as soon as the target thread next returns to
// user mode, which a running game does immediately.
//
// The request therefore carries a ThreadId (v3).  The APC object must outlive
// KeInsertQueueApc, so it lives in a pool context that the ioctl frees only
// after the kernel routine has run; if delivery never happens the context is
// left allocated rather than freed under a pending APC.
// ----------------------------------------------------------------------------
typedef struct _APEXDRV_APC_CONTEXT {
    KAPC      Apc;
    PVOID     RemotePath;      // pool-free candidate once Fired is set
    volatile LONG Fired;       // set by the kernel routine
} APEXDRV_APC_CONTEXT, *PAPEXDRV_APC_CONTEXT;

static VOID ApexdrvApcKernelRoutine(PKAPC apc, APEXDRV_KNORMAL_ROUTINE* normalRoutine,
                                    PVOID* normalContext, PVOID* systemArgument1,
                                    PVOID* systemArgument2) {
    PAPEXDRV_APC_CONTEXT context = CONTAINING_RECORD(apc, APEXDRV_APC_CONTEXT, Apc);

    UNREFERENCED_PARAMETER(normalRoutine);
    UNREFERENCED_PARAMETER(normalContext);
    UNREFERENCED_PARAMETER(systemArgument1);
    UNREFERENCED_PARAMETER(systemArgument2);

    InterlockedExchange(&context->Fired, 1);
}

// Queues LoadLibraryW(remotePath) in `process` on thread `threadId`.
// Returns immediately after the APC is queued; *contextOut owns the APC object
// and the caller is responsible for freeing it (see the delay in the caller).
static NTSTATUS ApexdrvQueueLoaderApc(PEPROCESS process, ULONG threadId,
                                      PVOID remotePath, ULONG_PTR loadLibrary,
                                      PAPEXDRV_APC_CONTEXT* contextOut) {
    PETHREAD            thread = NULL;
    PAPEXDRV_APC_CONTEXT context;
    NTSTATUS            status;

    *contextOut = NULL;

    if (threadId == 0) return STATUS_INVALID_PARAMETER;

    status = PsLookupThreadByThreadId(ULongToHandle(threadId), &thread);
    if (!NT_SUCCESS(status)) return status;

    // A TID from another process would make the APC land in the wrong address
    // space (the LoadLibrary address and the path buffer are per-process).
    if (IoThreadToProcess(thread) != process) {
        ObDereferenceObject(thread);
        return STATUS_INVALID_PARAMETER;
    }

    context = (PAPEXDRV_APC_CONTEXT)ExAllocatePoolWithTag(NonPagedPoolNx,
                                                          sizeof(*context),
                                                          APEXDRV_TAG);
    if (context == NULL) {
        ObDereferenceObject(thread);
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    RtlZeroMemory(context, sizeof(*context));
    context->RemotePath = remotePath;

    KeInitializeApc(&context->Apc,
                    thread,
                    OriginalApcEnvironment,
                    ApexdrvApcKernelRoutine,
                    (APEXDRV_KRUNDOWN_ROUTINE)NULL,         // rundown routine
                    (APEXDRV_KNORMAL_ROUTINE)loadLibrary,   // user-mode entry
                    UserMode,
                    remotePath);                            // RCX at delivery

    if (!KeInsertQueueApc(&context->Apc, NULL, NULL, 0)) {
        ExFreePoolWithTag(context, APEXDRV_TAG);
        ObDereferenceObject(thread);
        return STATUS_UNSUCCESSFUL;
    }

    ObDereferenceObject(thread);   // the queued APC holds its own reference
    *contextOut = context;
    return STATUS_SUCCESS;
}

// ----------------------------------------------------------------------------
// v4 loader instrumentation: read-only views into the target's loader state.
//
// Every offset below is the stable public x64 structure layout (PEB->Ldr at 0x18,
// LDR_DATA_TABLE_ENTRY.InLoadOrderLinks 0x00 / DllBase 0x30 / BaseDllName 0x58,
// TEB.LastErrorValue 0x68, PE32+ data directory 0x70).  All reads happen under
// KeStackAttachProcess inside __try/__except, so a target that unloads a module
// mid-walk costs one exception, never a bugcheck.
// ----------------------------------------------------------------------------
#define APEXDRV_PEB_LDR_OFFSET          0x18
#define APEXDRV_LDR_LIST_OFFSET         0x10
#define APEXDRV_LDR_DLLBASE_OFFSET      0x30
#define APEXDRV_LDR_BASENAME_OFFSET     0x58
#define APEXDRV_TEB_LASTERROR_OFFSET    0x68
#define APEXDRV_MAX_MODULES             1024
#define APEXDRV_MAX_EXPORT_NAMES        0x8000

typedef struct _APEXDRV_LDR_INFO {
    ULONG   Count;
    ULONG64 Kernel32Base;
    ULONG64 KernelBaseBase;
    ULONG64 LastBase;
    WCHAR   LastName[APEXDRV_MAX_MODULE_NAME_CHARS];
} APEXDRV_LDR_INFO, *PAPEXDRV_LDR_INFO;

// Caller must already be attached to the owner of `name`.
static BOOLEAN ApexdrvNameEquals(PCUNICODE_STRING name, const WCHAR* literal,
                                 SIZE_T literalChars) {
    WCHAR  buffer[APEXDRV_MAX_MODULE_NAME_CHARS];
    SIZE_T chars;
    SIZE_T index;

    if (name == NULL || name->Buffer == NULL || name->Length < 2) return FALSE;
    chars = name->Length / sizeof(WCHAR);
    if (chars >= APEXDRV_MAX_MODULE_NAME_CHARS) chars = APEXDRV_MAX_MODULE_NAME_CHARS - 1;
    for (index = 0; index < chars; ++index) buffer[index] = name->Buffer[index];
    buffer[chars] = L'\0';

    if (chars != literalChars) return FALSE;
    for (index = 0; index < chars; ++index) {
        WCHAR a = buffer[index];
        WCHAR b = literal[index];
        if (a >= L'A' && a <= L'Z') a = (WCHAR)(a + 32);
        if (b >= L'A' && b <= L'Z') b = (WCHAR)(b + 32);
        if (a != b) return FALSE;
    }
    return TRUE;
}

// Caller must already be attached to the owner of `text`.
static BOOLEAN ApexdrvAsciiEquals(const char* text, const char* wanted) {
    SIZE_T index;

    if (text == NULL || wanted == NULL) return FALSE;
    for (index = 0; index < 64; ++index) {
        if (text[index] != wanted[index]) return FALSE;
        if (wanted[index] == '\0') return TRUE;
    }
    return FALSE;
}

// Walks the target's InLoadOrder module list: reports the count, the two bases the
// resolver needs, and the last entry's base/name (the newest load in the list).
static NTSTATUS ApexdrvWalkModules(PEPROCESS process, PAPEXDRV_LDR_INFO info) {
    KAPC_STATE  apcState;
    NTSTATUS    status = STATUS_SUCCESS;
    PPEB        peb;
    PLIST_ENTRY head;
    PLIST_ENTRY entry;
    ULONG       guard = 0;

    RtlZeroMemory(info, sizeof(*info));

    peb = PsGetProcessPeb(process);
    if (peb == NULL) return STATUS_NOT_FOUND;

    KeStackAttachProcess(process, &apcState);
    __try {
        PVOID ldr = *(PVOID*)((PUCHAR)peb + APEXDRV_PEB_LDR_OFFSET);
        if (ldr == NULL) {
            status = STATUS_NOT_FOUND;
        } else {
            head  = (PLIST_ENTRY)((PUCHAR)ldr + APEXDRV_LDR_LIST_OFFSET);
            entry = head->Flink;
            while (entry != head && guard < APEXDRV_MAX_MODULES) {
                ULONG64          base = *(ULONG64*)((PUCHAR)entry + APEXDRV_LDR_DLLBASE_OFFSET);
                PCUNICODE_STRING name =
                    (PCUNICODE_STRING)((PUCHAR)entry + APEXDRV_LDR_BASENAME_OFFSET);
                PLIST_ENTRY      next = entry->Flink;
                ULONG            copy;
                ULONG            index;

                info->Count++;
                if (base != 0) {
                    // Reported as the newest entry: used to name the module that a
                    // successful LoadLibraryW appended.
                    info->LastBase = base;
                    if (name != NULL && name->Buffer != NULL && name->Length >= 2) {
                        copy = name->Length / sizeof(WCHAR);
                        if (copy >= APEXDRV_MAX_MODULE_NAME_CHARS) {
                            copy = APEXDRV_MAX_MODULE_NAME_CHARS - 1;
                        }
                        for (index = 0; index < copy; ++index) {
                            info->LastName[index] = name->Buffer[index];
                        }
                        info->LastName[copy] = L'\0';
                    }
                    if (ApexdrvNameEquals(name, L"kernel32.dll", 12)) {
                        info->Kernel32Base = base;
                    } else if (ApexdrvNameEquals(name, L"kernelbase.dll", 14)) {
                        info->KernelBaseBase = base;
                    }
                }
                entry = next;                   // cached before the next target read
                guard++;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
    }
    KeUnstackDetachProcess(&apcState);

    return status;
}

// Resolves `exportName` inside `imageBase` as mapped in `process` and returns its
// RVA.  kernelbase is used, not kernel32: kernel32 re-exports almost everything as
// forwarder strings, which would need a second parse for no benefit.
static NTSTATUS ApexdrvResolveExportRva(PEPROCESS process, ULONG64 imageBase,
                                        const char* exportName, PULONG rvaOut) {
    KAPC_STATE apcState;
    NTSTATUS   status = STATUS_NOT_FOUND;

    if (imageBase == 0 || exportName == NULL || rvaOut == NULL) {
        return STATUS_INVALID_PARAMETER;
    }
    *rvaOut = 0;

    KeStackAttachProcess(process, &apcState);
    __try {
        ULONG lfanew;
        ULONG directoryRva;
        ULONG directorySize;
        ULONG numberOfFunctions;
        ULONG numberOfNames;
        ULONG functionsRva;
        ULONG namesRva;
        ULONG ordinalsRva;
        ULONG index;
        PVOID   optionalHeader;

        if (*(USHORT*)((PUCHAR)imageBase) != 0x5A4D) {                   // 'MZ'
            status = STATUS_INVALID_IMAGE_FORMAT;
        } else {
            lfanew = *(ULONG*)((PUCHAR)imageBase + 0x3C);
            if (*(ULONG*)((PUCHAR)imageBase + lfanew) != 0x00004550) {  // 'PE\0\0'
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else {
                optionalHeader = (PUCHAR)imageBase + lfanew + 0x18;
                if (*(USHORT*)optionalHeader != 0x020B) {                // PE32+ only
                    status = STATUS_INVALID_IMAGE_FORMAT;
                } else {
                    directoryRva  = *(ULONG*)((PUCHAR)optionalHeader + 0x70);
                    directorySize = *(ULONG*)((PUCHAR)optionalHeader + 0x74);
                    if (directoryRva == 0 || directorySize == 0) {
                        status = STATUS_NOT_FOUND;
                    } else {
                        numberOfFunctions = *(ULONG*)((PUCHAR)imageBase + directoryRva + 0x14);
                        numberOfNames     = *(ULONG*)((PUCHAR)imageBase + directoryRva + 0x18);
                        functionsRva      = *(ULONG*)((PUCHAR)imageBase + directoryRva + 0x1C);
                        namesRva          = *(ULONG*)((PUCHAR)imageBase + directoryRva + 0x20);
                        ordinalsRva       = *(ULONG*)((PUCHAR)imageBase + directoryRva + 0x24);

                        if (numberOfNames > APEXDRV_MAX_EXPORT_NAMES) {
                            status = STATUS_INVALID_IMAGE_FORMAT;
                        } else {
                            for (index = 0; index < numberOfNames; ++index) {
                                ULONG     nameRva =
                                    *(ULONG*)((PUCHAR)imageBase + namesRva + index * 4);
                                const char* text =
                                    (const char*)((PUCHAR)imageBase + nameRva);

                                if (ApexdrvAsciiEquals(text, exportName)) {
                                    USHORT ordinal =
                                        *(USHORT*)((PUCHAR)imageBase + ordinalsRva + index * 2);
                                    if ((ULONG)ordinal < numberOfFunctions) {
                                        *rvaOut = *(ULONG*)((PUCHAR)imageBase +
                                                              functionsRva +
                                                              (ULONG)ordinal * 4);
                                        status = STATUS_SUCCESS;
                                    } else {
                                        status = STATUS_INVALID_IMAGE_FORMAT;
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
    }
    KeUnstackDetachProcess(&apcState);

    return status;
}

typedef PVOID (NTAPI *APEXDRV_PFN_GET_THREAD_TEB)(PETHREAD Thread);

// PsGetThreadTeb is documented but not always in the import library, so it is
// resolved once - the same treatment the other optional exports here get.
static APEXDRV_PFN_GET_THREAD_TEB ApexdrvGetThreadTebRoutine(VOID) {
    static APEXDRV_PFN_GET_THREAD_TEB cached   = NULL;
    static BOOLEAN                    resolved = FALSE;

    if (!resolved) {
        UNICODE_STRING routineName;

        RtlInitUnicodeString(&routineName, L"PsGetThreadTeb");
        cached = (APEXDRV_PFN_GET_THREAD_TEB)MmGetSystemRoutineAddress(&routineName);
        resolved = TRUE;
    }
    return cached;
}

// Reads TEB->LastErrorValue of `threadId`.  When the call ran and left no module
// behind, this is the only thing that says WHY (126 path, 193 image, 998, 1114).
static NTSTATUS ApexdrvReadThreadLastError(PEPROCESS process, ULONG threadId,
                                           PLONG valueOut) {
    KAPC_STATE                 apcState;
    PETHREAD                   thread = NULL;
    APEXDRV_PFN_GET_THREAD_TEB getTeb;
    PVOID                      teb;
    NTSTATUS                   status;

    if (threadId == 0 || valueOut == NULL) return STATUS_INVALID_PARAMETER;
    *valueOut = 0;

    getTeb = ApexdrvGetThreadTebRoutine();
    if (getTeb == NULL) return STATUS_PROCEDURE_NOT_FOUND;

    status = PsLookupThreadByThreadId(ULongToHandle(threadId), &thread);
    if (!NT_SUCCESS(status)) return status;

    if (IoThreadToProcess(thread) != process) {
        ObDereferenceObject(thread);
        return STATUS_INVALID_PARAMETER;
    }

    teb = getTeb(thread);
    if (teb == NULL) {
        ObDereferenceObject(thread);
        return STATUS_NOT_FOUND;
    }

    status = STATUS_SUCCESS;
    KeStackAttachProcess(process, &apcState);
    __try {
        *valueOut = *(LONG*)((PUCHAR)teb + APEXDRV_TEB_LASTERROR_OFFSET);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
    }
    KeUnstackDetachProcess(&apcState);

    ObDereferenceObject(thread);
    return status;
}

// The process/thread access masks are the stable NT ABI values.  wdm.h only
// defines the ones a filter driver historically needed (PROCESS_ALL_ACCESS,
// THREAD_TERMINATE, ...), so the ones this driver passes to ZwOpenProcess /
// ObReferenceObjectByHandle are pinned here, guarded so a WDK that does define
// them still wins.
#ifndef PROCESS_CREATE_THREAD
#define PROCESS_CREATE_THREAD       (0x0002)
#endif
#ifndef PROCESS_VM_OPERATION
#define PROCESS_VM_OPERATION        (0x0008)
#endif
#ifndef PROCESS_VM_READ
#define PROCESS_VM_READ             (0x0010)
#endif
#ifndef PROCESS_VM_WRITE
#define PROCESS_VM_WRITE            (0x0020)
#endif
#ifndef PROCESS_QUERY_INFORMATION
#define PROCESS_QUERY_INFORMATION   (0x0400)
#endif
#ifndef THREAD_QUERY_INFORMATION
#define THREAD_QUERY_INFORMATION    (0x0040)
#endif

#define APEXDRV_MAX_THREAD_WAIT_MS  5000

// Tagged working buffer — proves APEXDRV_TAG is a real pool tag, not dead code.
static UCHAR* g_ProbePattern = NULL;

static PDEVICE_OBJECT g_DeviceObject  = NULL;
static BOOLEAN        g_SymlinkCreated = FALSE;

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
static NTSTATUS ApexdrvOpenProcess(ULONG processId, HANDLE* processHandle,
                                   PEPROCESS* process) {
    CLIENT_ID clientId = { 0 };
    OBJECT_ATTRIBUTES attributes;
    NTSTATUS status;

    *process = NULL;

    // The process OBJECT is needed for the two operations the 26100 import
    // library does not carry (attach-and-copy and MmCopyVirtualMemory), so it is
    // taken first; a failure below releases it, so the pair can never leak.
    status = PsLookupProcessByProcessId(ULongToHandle(processId), process);
    if (!NT_SUCCESS(status)) return status;

    clientId.UniqueProcess = ULongToHandle(processId);
    clientId.UniqueThread  = NULL;

    InitializeObjectAttributes(&attributes, NULL, OBJ_KERNEL_HANDLE, NULL, NULL);

    status = ZwOpenProcess(processHandle,
                           PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION |
                           PROCESS_VM_WRITE | PROCESS_VM_READ |
                           PROCESS_QUERY_INFORMATION,
                           &attributes, &clientId);
    if (!NT_SUCCESS(status)) {
        ObDereferenceObject(*process);
        *process = NULL;
    }
    return status;
}

// ----------------------------------------------------------------------------
// IOCTL_APEXDRV_INJECT
// ----------------------------------------------------------------------------
static NTSTATUS ApexdrvInject(PAPEXDRV_INJECT_REQUEST request) {
    HANDLE    processHandle = NULL;
    PEPROCESS process       = NULL;
    PVOID     remoteBuffer  = NULL;
    SIZE_T    regionSize    = 0;
    SIZE_T    pathBytes     = 0;
    NTSTATUS  status;
    ULONG     i;
    LONG      fired         = 0;
    LARGE_INTEGER delay;
    PAPEXDRV_APC_CONTEXT apcContext = NULL;
    APEXDRV_LDR_INFO    targetInfo;
    APEXDRV_LDR_INFO    selfInfo;
    ULONG               exportRva   = 0;
    ULONG64             loadLibrary = request->LoadLibraryAddress;

    if (request->ProcessId == 0) return STATUS_INVALID_PARAMETER;
    if (request->ThreadId == 0)  return STATUS_INVALID_PARAMETER;
    if (request->LoadLibraryAddress == 0 &&
        (request->Flags & APEXDRV_FLAG_RESOLVE_IN_TARGET) == 0) {
        return STATUS_INVALID_PARAMETER;
    }

    request->ResultStatus         = STATUS_SUCCESS;   // overwritten on every failure
    request->ResolvedLoadLibrary  = 0;
    request->ResolvePath          = 0;
    request->BasesDiffer          = 0;
    request->ModuleCountBefore    = 0;
    request->ModuleCountAfter     = 0;
    request->NewModuleBase        = 0;
    request->NewModuleName[0]     = L'\0';
    request->LoadLibraryLastError = 0;
    request->StatusReadResult     = 0;
    request->StatusEchoRead       = 0;
    request->RemotePathEcho[0]    = L'\0';
    request->FiredSeen            = 0;
    request->StatusEchoAfter      = 0;
    request->RemotePathEchoAfter[0] = L'\0';
    request->StatusReadResult2    = 0;
    request->LoadLibraryLastError2 = 0;
    request->ModuleCountAfter2    = 0;

    // Ensure the wide path is NUL terminated inside the supplied buffer.
    request->DllPath[APEXDRV_MAX_PATH_CHARS - 1] = L'\0';
    pathBytes = (wcslen(request->DllPath) + 1) * sizeof(WCHAR);
    if (pathBytes <= sizeof(WCHAR)) return STATUS_INVALID_PARAMETER;

    status = ApexdrvOpenProcess(request->ProcessId, &processHandle, &process);
    if (!NT_SUCCESS(status)) {
        request->ResultStatus = status;
        return status;
    }

    // v4: the address the launcher resolved in ITS OWN address space is only a
    // guess - kernel32/kernelbase are ASLR-placed and a per-process difference
    // makes LoadLibraryW land in the middle of something.  Resolve it in the
    // target and measure the premise while doing so (BasesDiffer).
    status = ApexdrvWalkModules(process, &targetInfo);
    if (!NT_SUCCESS(status)) {
        request->ResultStatus = status;
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }
    request->ModuleCountBefore = targetInfo.Count;

    status = ApexdrvWalkModules(PsGetCurrentProcess(), &selfInfo);
    if (NT_SUCCESS(status) && targetInfo.KernelBaseBase != 0 &&
        selfInfo.KernelBaseBase != 0 &&
        targetInfo.KernelBaseBase != selfInfo.KernelBaseBase) {
        request->BasesDiffer = 1;
    }

    if (request->Flags & APEXDRV_FLAG_RESOLVE_IN_TARGET) {
        status = ApexdrvResolveExportRva(process, targetInfo.KernelBaseBase,
                                         "LoadLibraryW", &exportRva);
        if (!NT_SUCCESS(status)) {
            request->ResultStatus = status;
            ZwClose(processHandle);
            ObDereferenceObject(process);
            return status;
        }
        loadLibrary = targetInfo.KernelBaseBase + exportRva;
        request->ResolvePath = 1;
    }
    request->ResolvedLoadLibrary = loadLibrary;

    regionSize = pathBytes;
    status = ZwAllocateVirtualMemory(processHandle, &remoteBuffer, 0, &regionSize,
                                     MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!NT_SUCCESS(status)) {
        request->ResultStatus = status;
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }

    status = ApexdrvWriteProcessMemory(process, remoteBuffer,
                                       request->DllPath, pathBytes);
    if (!NT_SUCCESS(status)) {
        request->ResultStatus = status;
        ZwFreeVirtualMemory(processHandle, &remoteBuffer, &regionSize, MEM_RELEASE);
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }

    // v5: show the bytes instead of trusting the copy's return status.
    request->StatusEchoRead = ApexdrvReadProcessMemory(process, remoteBuffer,
                                                       request->RemotePathEcho,
                                                       pathBytes);
    request->RemotePathEcho[APEXDRV_MAX_PATH_CHARS - 1] = L'\0';

    // Queue LoadLibraryW(remotePath) on the caller's thread instead of creating
    // one: see the block comment above ApexdrvQueueLoaderApc for why.
    status = ApexdrvQueueLoaderApc(process, request->ThreadId, remoteBuffer,
                                   (ULONG_PTR)loadLibrary,
                                   &apcContext);
    if (!NT_SUCCESS(status)) {
        request->ResultStatus = status;
        ZwFreeVirtualMemory(processHandle, &remoteBuffer, &regionSize, MEM_RELEASE);
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }

    // The APC only fires when the thread next returns to user mode, which takes
    // it out of a wait / syscall.  Poll the kernel routine's flag so the path
    // buffer and the APC context are not freed under a pending APC.
    delay.QuadPart = -10 * 10000;                  // 10 ms
    for (i = 0; i < 300; i++) {                    // 3 s cap
        fired = InterlockedCompareExchange(&apcContext->Fired, 0, 0);
        if (fired != 0) break;
        KeDelayExecutionThread(KernelMode, FALSE, &delay);
    }

    request->RemoteBase = (ULONG64)(ULONG_PTR)remoteBuffer;
    request->FiredSeen  = (ULONG)fired;

    if (fired == 0) {
        // Still queued: keep the context AND the path buffer, they are in use.
        // v5 still reports both samples, so "never fired" is distinguishable from
        // "fired and failed" without another numbered run.
        request->StatusEchoAfter = ApexdrvReadProcessMemory(
            process, remoteBuffer, request->RemotePathEchoAfter,
            pathBytes < sizeof(request->RemotePathEchoAfter)
                ? pathBytes
                : sizeof(request->RemotePathEchoAfter) - sizeof(WCHAR));
        request->RemotePathEchoAfter[APEXDRV_MAX_MODULE_NAME_CHARS - 1] = L'\0';
        request->StatusReadResult2 =
            ApexdrvReadThreadLastError(process, request->ThreadId,
                                       &request->LoadLibraryLastError2);
        if (NT_SUCCESS(ApexdrvWalkModules(process, &targetInfo))) {
            request->ModuleCountAfter2 = targetInfo.Count;
        }
        request->ResultStatus = STATUS_PENDING;
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return STATUS_SUCCESS;
    }

    // The kernel routine has run; the user-mode entry still needs a moment to
    // read the path before it is released.
    delay.QuadPart = -200 * 10000;                 // 200 ms
    KeDelayExecutionThread(KernelMode, FALSE, &delay);

    // v4 verdict data: did the loader actually append a module, and if not, what
    // did the call leave in LastError?  `Fired` alone only says "the APC ran".
    request->StatusReadResult =
        ApexdrvReadThreadLastError(process, request->ThreadId,
                                   &request->LoadLibraryLastError);

    status = ApexdrvWalkModules(process, &targetInfo);
    if (NT_SUCCESS(status)) {
        request->ModuleCountAfter = targetInfo.Count;
        if (targetInfo.Count > request->ModuleCountBefore) {
            // RtlStringCchCopyW would need ntstrsafe.h; the source is already
            // bounded and NUL-terminated by the walk, so a plain copy is enough.
            ULONG nameIndex;
            for (nameIndex = 0;
                 nameIndex < APEXDRV_MAX_MODULE_NAME_CHARS - 1 &&
                 targetInfo.LastName[nameIndex] != L'\0';
                 ++nameIndex) {
                request->NewModuleName[nameIndex] = targetInfo.LastName[nameIndex];
            }
            request->NewModuleName[nameIndex] = L'\0';
            request->NewModuleBase = targetInfo.LastBase;
        }
    }

    // v5: echo + a second sample 1 s later.  A loader that finishes after our
    // 200 ms window would otherwise be scored as "no module".
    request->StatusEchoAfter = ApexdrvReadProcessMemory(
        process, remoteBuffer, request->RemotePathEchoAfter,
        pathBytes < sizeof(request->RemotePathEchoAfter)
            ? pathBytes
            : sizeof(request->RemotePathEchoAfter) - sizeof(WCHAR));
    request->RemotePathEchoAfter[APEXDRV_MAX_MODULE_NAME_CHARS - 1] = L'\0';

    delay.QuadPart = -800 * 10000;                 // + 800 ms = 1 s after delivery
    KeDelayExecutionThread(KernelMode, FALSE, &delay);

    request->StatusReadResult2 =
        ApexdrvReadThreadLastError(process, request->ThreadId,
                                   &request->LoadLibraryLastError2);
    if (NT_SUCCESS(ApexdrvWalkModules(process, &targetInfo))) {
        request->ModuleCountAfter2 = targetInfo.Count;
    }

    request->ResultStatus = STATUS_SUCCESS;

    ExFreePoolWithTag(apcContext, APEXDRV_TAG);
    // The path buffer is NOT freed here: the kernel routine runs at delivery,
    // the user routine (LoadLibraryW) runs later on the thread's return to user
    // mode and would then read freed memory.  ~260 bytes per injection is cheap
    // insurance, and the address is reported back as RemoteBase either way.
    ZwClose(processHandle);
    ObDereferenceObject(process);

    return STATUS_SUCCESS;
}

// ----------------------------------------------------------------------------
// IOCTL_APEXDRV_PROBE — does the target accept work issued from KERNEL context?
//
// Mirrors the user-mode probe exactly: lookup -> open with injector rights ->
// allocate/write/free -> copy the PEB out.  Each step's NTSTATUS is stored so a
// partial result (e.g. handle fine, allocation refused) is still evidence.
// Deliberately returns STATUS_SUCCESS when the request was understood: the
// caller reads the per-step statuses, and a driver-side failure would hide
// which step produced it.
//
// Runs at PASSIVE_LEVEL in the requesting thread's context (synchronous
// DeviceIoControl), which is what PsLookupProcessByProcessId, ObOpenObjectByPointer
// and MmCopyVirtualMemory all require.
// ----------------------------------------------------------------------------
static NTSTATUS ApexdrvProbeProcess(PAPEXDRV_PROBE_REQUEST request) {
    PEPROCESS process       = NULL;
    HANDLE    processHandle = NULL;
    PVOID     remoteBuffer  = NULL;
    SIZE_T    regionSize    = 0x1000;
    SIZE_T    bytesCopied   = 0;
    NTSTATUS  status;
    UCHAR     pattern       = 0xA5;

    if (request->ProcessId == 0) return STATUS_INVALID_PARAMETER;

    // Zero the entire output buffer so no field leaks stale/garbage data.  The
    // buffer IS the request, so ProcessId has to be saved: zeroing it first made
    // every probe answer PsLookupProcessByProcessId(0) = STATUS_INVALID_PARAMETER
    // and looked exactly like a kernel-side refusal.
    {
        ULONG processId = request->ProcessId;
        RtlZeroMemory(request, sizeof(*request));
        request->ProcessId = processId;
    }

    status = PsLookupProcessByProcessId(ULongToHandle(request->ProcessId), &process);
    request->StatusLookup = status;
    if (!NT_SUCCESS(status)) return STATUS_SUCCESS;

    // Reading the PEB address needs no handle and no access check at all.
    request->PebAddress = (ULONG64)(ULONG_PTR)PsGetProcessPeb(process);

    status = ObOpenObjectByPointer(process, OBJ_KERNEL_HANDLE, NULL,
                                   PROCESS_ALL_ACCESS, NULL, KernelMode,
                                   &processHandle);
    request->StatusOpen = status;

    if (NT_SUCCESS(status)) {
        status = ZwAllocateVirtualMemory(processHandle, &remoteBuffer, 0, &regionSize,
                                        MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        request->StatusAllocate   = status;
        request->RemoteAllocation = (ULONG64)(ULONG_PTR)remoteBuffer;

        if (NT_SUCCESS(status)) {
            request->StatusWrite =
                ApexdrvWriteProcessMemory(process, remoteBuffer, &pattern,
                                          sizeof(pattern));
            request->StatusFree =
                ZwFreeVirtualMemory(processHandle, &remoteBuffer, &regionSize,
                                    MEM_RELEASE);
        }

        ZwClose(processHandle);
    }

    // Independent of the handle path: MmCopyVirtualMemory needs only the
    // EPROCESS, so it still answers when ObOpenObjectByPointer was refused.
    if (request->PebAddress != 0) {
        request->StatusCopyVirtual = MmCopyVirtualMemory(
            process, (PVOID)(ULONG_PTR)request->PebAddress,
            PsGetCurrentProcess(), request->Bytes,
            sizeof(request->Bytes), KernelMode, &bytesCopied);
        request->BytesCopied = (ULONG)bytesCopied;
    } else {
        request->StatusCopyVirtual = STATUS_INVALID_PARAMETER;
    }

    ObDereferenceObject(process);
    return STATUS_SUCCESS;
}

// ----------------------------------------------------------------------------
// IOCTL_APEXDRV_TARGETINFO (v4) — read-only loader facts about one target.
//
// Nothing is allocated or written in the target.  The two walks run under
// KeStackAttachProcess in the requesting thread's context (PASSIVE_LEVEL), and
// every output field that could not be measured keeps its zero.
// ----------------------------------------------------------------------------
static NTSTATUS ApexdrvTargetInfo(PAPEXDRV_TARGETINFO_REQUEST request) {
    PEPROCESS        process = NULL;
    APEXDRV_LDR_INFO targetInfo;
    APEXDRV_LDR_INFO selfInfo;
    ULONG            processId;
    ULONG            threadId;
    ULONG            rva = 0;
    NTSTATUS         status;

    // The output buffer IS the request buffer, so the two in-fields are saved
    // before the zeroing that clears stale data (the probe handler originally
    // lost ProcessId this way and always answered STATUS_INVALID_PARAMETER).
    processId = request->ProcessId;
    threadId  = request->ThreadId;
    if (processId == 0) return STATUS_INVALID_PARAMETER;

    RtlZeroMemory(request, sizeof(*request));
    request->ProcessId = processId;
    request->ThreadId  = threadId;

    status = PsLookupProcessByProcessId(ULongToHandle(processId), &process);
    request->StatusLookup = status;
    if (!NT_SUCCESS(status)) return STATUS_SUCCESS;

    request->StatusWalk     = ApexdrvWalkModules(process, &targetInfo);
    request->StatusSelfWalk = ApexdrvWalkModules(PsGetCurrentProcess(), &selfInfo);

    request->ModuleCount       = targetInfo.Count;
    request->SelfModuleCount   = selfInfo.Count;
    request->Kernel32Base      = targetInfo.Kernel32Base;
    request->KernelBaseBase    = targetInfo.KernelBaseBase;
    request->SelfKernel32Base  = selfInfo.Kernel32Base;
    request->SelfKernelBaseBase = selfInfo.KernelBaseBase;

    if (targetInfo.KernelBaseBase != 0 && selfInfo.KernelBaseBase != 0 &&
        targetInfo.KernelBaseBase != selfInfo.KernelBaseBase) {
        request->BasesDiffer = 1;
    }

    request->StatusResolve = ApexdrvResolveExportRva(
        process, targetInfo.KernelBaseBase, "LoadLibraryW", &rva);
    if (NT_SUCCESS(request->StatusResolve)) {
        request->LoadLibraryRva      = rva;
        request->ResolvedLoadLibrary = targetInfo.KernelBaseBase + rva;
    }

    if (threadId != 0) {
        request->StatusReadResult =
            ApexdrvReadThreadLastError(process, threadId, &request->LastErrorValue);
    }

    ObDereferenceObject(process);
    return STATUS_SUCCESS;
}

// ----------------------------------------------------------------------------
// IRP dispatch
// ----------------------------------------------------------------------------
static NTSTATUS ApexdrvCreateClose(PDEVICE_OBJECT deviceObject, PIRP irp) {
    UNREFERENCED_PARAMETER(deviceObject);

    irp->IoStatus.Status      = STATUS_SUCCESS;
    irp->IoStatus.Information = 0;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

static NTSTATUS ApexdrvDeviceControl(PDEVICE_OBJECT deviceObject, PIRP irp) {
    PIO_STACK_LOCATION stack;
    ULONG    code;
    ULONG    inputLength;
    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;
    ULONG    information = 0;

    UNREFERENCED_PARAMETER(deviceObject);

    stack       = IoGetCurrentIrpStackLocation(irp);
    code        = stack->Parameters.DeviceIoControl.IoControlCode;
    inputLength = stack->Parameters.DeviceIoControl.InputBufferLength;

    switch (code) {
        case IOCTL_APEXDRV_VERSION:
            if (inputLength >= sizeof(APEXDRV_VERSION_INFO) &&
                irp->AssociatedIrp.SystemBuffer != NULL) {
                PAPEXDRV_VERSION_INFO info =
                    (PAPEXDRV_VERSION_INFO)irp->AssociatedIrp.SystemBuffer;
                info->Version  = APEXDRV_VERSION;
                info->Reserved = 0;
                information = sizeof(APEXDRV_VERSION_INFO);
                status = STATUS_SUCCESS;
            } else {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            break;

        case IOCTL_APEXDRV_INJECT:
            if (inputLength >= sizeof(APEXDRV_INJECT_REQUEST) &&
                irp->AssociatedIrp.SystemBuffer != NULL) {
                status = ApexdrvInject(
                    (PAPEXDRV_INJECT_REQUEST)irp->AssociatedIrp.SystemBuffer);
                information = sizeof(APEXDRV_INJECT_REQUEST);
            } else {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            break;

        case IOCTL_APEXDRV_PROBE:
            if (inputLength >= sizeof(APEXDRV_PROBE_REQUEST) &&
                irp->AssociatedIrp.SystemBuffer != NULL) {
                status = ApexdrvProbeProcess(
                    (PAPEXDRV_PROBE_REQUEST)irp->AssociatedIrp.SystemBuffer);
                information = sizeof(APEXDRV_PROBE_REQUEST);
            } else {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            break;

        case IOCTL_APEXDRV_TARGETINFO:
            if (inputLength >= sizeof(APEXDRV_TARGETINFO_REQUEST) &&
                irp->AssociatedIrp.SystemBuffer != NULL) {
                status = ApexdrvTargetInfo(
                    (PAPEXDRV_TARGETINFO_REQUEST)irp->AssociatedIrp.SystemBuffer);
                information = sizeof(APEXDRV_TARGETINFO_REQUEST);
            } else {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            break;

        default:
            break;
    }

    irp->IoStatus.Status      = status;
    irp->IoStatus.Information = information;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}

static VOID ApexdrvUnload(PDRIVER_OBJECT driverObject) {
    UNICODE_STRING symlink;

    UNREFERENCED_PARAMETER(driverObject);

    if (g_SymlinkCreated) {
        RtlInitUnicodeString(&symlink, APEXDRV_SYMLINK_NAME);
        IoDeleteSymbolicLink(&symlink);
        g_SymlinkCreated = FALSE;
    }
    if (g_DeviceObject != NULL) {
        IoDeleteDevice(g_DeviceObject);
        g_DeviceObject = NULL;
    }
}

// ----------------------------------------------------------------------------
// DriverEntry
// ----------------------------------------------------------------------------
NTSTATUS DriverEntry(PDRIVER_OBJECT driverObject, PUNICODE_STRING registryPath) {
    UNICODE_STRING deviceName;
    UNICODE_STRING symlink;
    NTSTATUS status;

    UNREFERENCED_PARAMETER(registryPath);

    RtlInitUnicodeString(&deviceName, APEXDRV_DEVICE_NAME);

    status = IoCreateDevice(driverObject, 0, &deviceName, APEXDRV_DEVICE_TYPE,
                            FILE_DEVICE_SECURE_OPEN, FALSE, &g_DeviceObject);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    RtlInitUnicodeString(&symlink, APEXDRV_SYMLINK_NAME);
    status = IoCreateSymbolicLink(&symlink, &deviceName);
    if (!NT_SUCCESS(status)) {
        IoDeleteDevice(g_DeviceObject);
        g_DeviceObject = NULL;
        return status;
    }
    g_SymlinkCreated = TRUE;

    driverObject->MajorFunction[IRP_MJ_CREATE]         = ApexdrvCreateClose;
    driverObject->MajorFunction[IRP_MJ_CLOSE]          = ApexdrvCreateClose;
    driverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = ApexdrvDeviceControl;
    driverObject->DriverUnload                          = ApexdrvUnload;

    return STATUS_SUCCESS;
}
