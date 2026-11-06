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

// v6 stub.  Written into the target and used as the APC entry instead of LoadLibraryW, so the
// two remaining questions stop being guesses: the first instruction stamps a magic (did ANY
// user-mode code run?) and the second stores RCX (what did the routine actually receive?),
// then it jumps to the loader entry so delivery still happens normally.
//
// v8 widens the code to 38 bytes so the Ex loader arm can also set its two arguments, and the
// data slots move with it.  One fixed layout either way, so a flag never shifts the offsets:
//
//   mov qword ptr [rip+0x1B], 0x4870    48 C7 05 1B 00 00 00 70 48 00 00   (11 bytes, [0,11))
//   mov [rip+0x1C], rcx                 48 89 0D 1C 00 00 00               ( 7 bytes, [11,18))
//   Ex arm only:  xor edx,edx           31 D2                              ( 2 bytes, [18,20))
//                 mov r8d, 8            41 B8 08 00 00 00                  ( 6 bytes, [20,26))
//   (non-Ex arm pads [18,26) with 8 NOPs instead)
//   mov rax, <entry>                    48 B8 <imm64>                      (10 bytes, [26,36))
//   jmp rax                             FF E0                              ( 2 bytes, [36,38))
//   data: entered at +38, rcx at +46
//
// The displacements are deltas from the END of their own instruction, never the absolute data
// offset: [0,11) ends at 11 so the magic slot +38 needs 38-11 = 27 (0x1B), and [11,18) ends at
// 18 so the rcx slot +46 needs 46-18 = 28 (0x1C).  v6 wrote the absolute values and both stores
// landed past the data slots (h278).
#define APEXDRV_STUB_CODE_BYTES   38
#define APEXDRV_STUB_DATA_BYTES   16
#define APEXDRV_STUB_TOTAL_BYTES  (APEXDRV_STUB_CODE_BYTES + APEXDRV_STUB_DATA_BYTES)
#define APEXDRV_STUB_MAGIC        0x4870UL

static void ApexdrvStampStub(PUCHAR stub, ULONG64 routine, BOOLEAN exLoader) {
    RtlZeroMemory(stub, APEXDRV_STUB_TOTAL_BYTES);
    // mov qword ptr [rip+0x1B], imm32  -> data slot at +38
    stub[0] = 0x48; stub[1] = 0xC7; stub[2] = 0x05;
    *(ULONG*)(stub + 3) = (ULONG)(APEXDRV_STUB_CODE_BYTES - 11);   // 38 - 11 = 27 = 0x1B
    *(ULONG*)(stub + 7) = APEXDRV_STUB_MAGIC;
    // mov [rip+0x1C], rcx  -> data slot at +46
    stub[11] = 0x48; stub[12] = 0x89; stub[13] = 0x0D;
    *(ULONG*)(stub + 14) = (ULONG)(APEXDRV_STUB_CODE_BYTES + 8 - 18);  // 46 - 18 = 28 = 0x1C
    if (exLoader) {
        // LoadLibraryExW(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH)
        stub[18] = 0x31; stub[19] = 0xD2;               // xor edx,edx   (RDX = 0)
        stub[20] = 0x41; stub[21] = 0xB8;               // mov r8d, 8    (R8  = 0x8)
        *(ULONG*)(stub + 22) = 8;
    } else {
        ULONG pad;
        for (pad = 0; pad < 8; ++pad) { stub[18 + pad] = 0x90; }   // keep the layout fixed
    }
    // mov rax, imm64 ; jmp rax
    stub[26] = 0x48; stub[27] = 0xB8;
    *(ULONG64*)(stub + 28) = routine;
    stub[36] = 0xFF; stub[37] = 0xE0;
}

// v9 map stub.  The manual-map entry, so the delivery no longer depends on any loader API:
// stamp the magic, store RCX (== the image base the driver passed as NormalContext), then
// call the mapped entry point as DllMain(base, DLL_PROCESS_ATTACH, NULL) and keep its BOOL.
//
// Unlike the loader stub this one must RETURN, not jump: the APC dispatcher put a return
// address on the stack and continues in KiUserApcDispatcher when the routine returns.
// The callee also needs the x64 ABI shape a `call` normally provides, so the stub realigns
// the stack itself: at routine entry RSP%16 is 8, `sub rsp,0x28` (32 B shadow + 8 B realign)
// makes it 0 for the call, and `add rsp,0x28` restores it before the `ret`.
//
//   mov qword ptr [rip+0x35], 0x4870    48 C7 05 35 00 00 00 70 48 00 00   (11 B, [0,11))
//   mov [rip+0x36], rcx                 48 89 0D 36 00 00 00               ( 7 B, [11,18))
//   mov rax, <entry>                    48 B8 <imm64>                      (10 B, [18,28))
//   mov edx, 1                          BA 01 00 00 00                     ( 5 B, [28,33))
//   xor r8d, r8d                        45 33 C0                           ( 3 B, [33,36))
//   sub rsp, 0x28                       48 83 EC 28                        ( 4 B, [36,40))
//   call rax                            FF D0                              ( 2 B, [40,42))
//   add rsp, 0x28                       48 83 C4 28                        ( 4 B, [42,46))
//   mov [rip+0x1B], rax                 48 89 05 1B 00 00 00               ( 7 B, [46,53))
//   mov dword [rip+0x19], 0x4871         C7 05 19 00 00 00 71 48 00 00     (10 B, [53,63))
//   ret                                 C3                                 ( 1 B, [63,64))
//   data: entered at +64, rcx at +72, result at +80, DONE flag at +88
//
// Displacements are deltas from the end of their OWN instruction: +64 needs 64-11 = 53 (0x35),
// +72 needs 72-18 = 54 (0x36), +80 needs 80-53 = 27 (0x1B), +88 needs 88-63 = 25 (0x19).
//
// v13: the DONE store is the point of this layout change.  The driver used to poll for
// "result != 0", so a DllMain that returned FALSE (RAX = 0) was indistinguishable from a
// DllMain still running or crashed: both burned the whole 10 s poll and both came back
// entryResult = 0.  The stub now stamps APEXDRV_MAP_STUB_DONE right after storing RAX, so
// the poll breaks on the flag and "returned FALSE" / "never returned" are different rows.
//
// `mov edx, 1` is a 32-bit write, not `mov dl, 1`: DllMain's reason is a DWORD and the upper
// bits of RDX arrive as the dispatcher's SystemArgument1, so a byte store would hand DllMain
// a stale reason (measured on the host: 0x0B550001 instead of 1) and its `== DLL_PROCESS_ATTACH`
// test would fail.
#define APEXDRV_MAP_STUB_CODE_BYTES  64
#define APEXDRV_MAP_STUB_DATA_BYTES  32   /* magic, rcx, entry result, DONE flag */
#define APEXDRV_MAP_STUB_TOTAL_BYTES (APEXDRV_MAP_STUB_CODE_BYTES + APEXDRV_MAP_STUB_DATA_BYTES)
#define APEXDRV_MAP_STUB_DONE        0x4871  /* stamped after the entry RETURNS (see above) */

static void ApexdrvStampMapStub(PUCHAR stub, ULONG64 entry) {
    RtlZeroMemory(stub, APEXDRV_MAP_STUB_TOTAL_BYTES);
    stub[0] = 0x48; stub[1] = 0xC7; stub[2] = 0x05;                 // magic -> +64
    *(ULONG*)(stub + 3) = APEXDRV_MAP_STUB_CODE_BYTES - 11;
    *(ULONG*)(stub + 7) = APEXDRV_STUB_MAGIC;
    stub[11] = 0x48; stub[12] = 0x89; stub[13] = 0x0D;               // rcx   -> +72
    *(ULONG*)(stub + 14) = (APEXDRV_MAP_STUB_CODE_BYTES + 8) - 18;
    stub[18] = 0x48; stub[19] = 0xB8;                                // mov rax, entry
    *(ULONG64*)(stub + 20) = entry;
    stub[28] = 0xBA;                                                 // mov edx, DLL_PROCESS_ATTACH
    *(ULONG*)(stub + 29) = 1;
    stub[33] = 0x45; stub[34] = 0x33; stub[35] = 0xC0;               // xor r8d, r8d (reserved)
    stub[36] = 0x48; stub[37] = 0x83; stub[38] = 0xEC; stub[39] = 0x28;  // sub rsp, 28h
    stub[40] = 0xFF; stub[41] = 0xD0;                                // call rax
    stub[42] = 0x48; stub[43] = 0x83; stub[44] = 0xC4; stub[45] = 0x28;  // add rsp, 28h
    stub[46] = 0x48; stub[47] = 0x89; stub[48] = 0x05;               // result -> +80
    *(ULONG*)(stub + 49) = (APEXDRV_MAP_STUB_CODE_BYTES + 16) - 53;
    stub[53] = 0xC7; stub[54] = 0x05;                                // DONE flag -> +88
    *(ULONG*)(stub + 55) = (APEXDRV_MAP_STUB_CODE_BYTES + 24) - 63;
    *(ULONG*)(stub + 59) = APEXDRV_MAP_STUB_DONE;
    stub[63] = 0xC3;                                                 // ret to the dispatcher
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
#define APEXDRV_MAX_FORWARDER_DEPTH     2

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
// Manual map (v9).  The loader is not involved at all, so nothing here depends on
// Ldr state inside the target.
// ----------------------------------------------------------------------------
// A SizeOfImage above this is a corrupt or hostile header, not a cheat payload.
#define APEXDRV_IMAGE_MAX_BYTES  (64UL * 1024 * 1024)
#define APEXDRV_IMAGE_MAX_SECTIONS 96UL

// The km headers used here do not pull in ntimage.h's section type, and the layout
// is fixed by the PE spec anyway (40 bytes: 8-byte Name, then the fields used at
// 8/12/16/20).  The Name array is not read, but it MUST be present - leaving it out
// shifts every field 8 bytes early and h284 failed the copy bounds on VirtualSize
// being taken for PointerToRawData.
typedef struct _APEXDRV_SECTION_HEADER {
    UCHAR  Name[8];
    ULONG  VirtualSize;
    ULONG  VirtualAddress;
    ULONG  SizeOfRawData;
    ULONG  PointerToRawData;
    ULONG  PointerToRelocations;
    ULONG  PointerToLinenumbers;
    USHORT NumberOfRelocations;
    USHORT NumberOfLinenumbers;
    ULONG  Characteristics;
} APEXDRV_SECTION_HEADER, *PAPEXDRV_SECTION_HEADER;

// Read the whole file into paged pool.  The driver does the read so no user-mode
// handle or IO is involved; SYSTEM can read the staging directories.
static NTSTATUS ApexdrvReadImageFile(PCWSTR path, PVOID* bufferOut, ULONG* sizeOut) {
    UNICODE_STRING      ntPath;
    OBJECT_ATTRIBUTES   attributes;
    IO_STATUS_BLOCK     iosb;
    FILE_STANDARD_INFORMATION fsi;
    HANDLE              file = NULL;
    WCHAR*              ntBuffer;
    PVOID               buffer = NULL;
    size_t              length;
    NTSTATUS            status;

    *bufferOut = NULL;
    *sizeOut   = 0;
    length = wcslen(path);
    if (length == 0 || length > 300) return STATUS_INVALID_PARAMETER;

    ntBuffer = (WCHAR*)ExAllocatePoolWithTag(PagedPool,
                                             (length + 5) * sizeof(WCHAR),
                                             APEXDRV_TAG);
    if (ntBuffer == NULL) return STATUS_INSUFFICIENT_RESOURCES;
    ntBuffer[0] = L'\\'; ntBuffer[1] = L'?'; ntBuffer[2] = L'?'; ntBuffer[3] = L'\\';
    RtlCopyMemory(ntBuffer + 4, path, (length + 1) * sizeof(WCHAR));
    RtlInitUnicodeString(&ntPath, ntBuffer);
    InitializeObjectAttributes(&attributes, &ntPath,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);

    status = ZwCreateFile(&file, GENERIC_READ | SYNCHRONIZE, &attributes, &iosb, NULL,
                          FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FILE_OPEN,
                          FILE_SYNCHRONOUS_IO_NONALERT | FILE_NON_DIRECTORY_FILE, NULL, 0);
    ExFreePoolWithTag(ntBuffer, APEXDRV_TAG);
    if (!NT_SUCCESS(status)) return status;

    status = ZwQueryInformationFile(file, &iosb, &fsi, sizeof(fsi),
                                    FileStandardInformation);
    if (NT_SUCCESS(status)) {
        // 0x100, not 0x1000: the header check below uses the same floor, and a
        // payload with no imports/CRT can legitimately be 2 KB (apxprobe.dll is).
        if (fsi.EndOfFile.QuadPart < 0x100 ||
            fsi.EndOfFile.QuadPart > APEXDRV_IMAGE_MAX_BYTES) {
            status = STATUS_INVALID_IMAGE_FORMAT;
        } else {
            *sizeOut = (ULONG)fsi.EndOfFile.QuadPart;
            buffer = ExAllocatePoolWithTag(PagedPool, *sizeOut, APEXDRV_TAG);
            if (buffer == NULL) {
                status = STATUS_INSUFFICIENT_RESOURCES;
            } else {
                status = ZwReadFile(file, NULL, NULL, NULL, &iosb, buffer, *sizeOut,
                                    NULL, NULL);
                if (NT_SUCCESS(status)) {
                    *bufferOut = buffer;
                } else {
                    ExFreePoolWithTag(buffer, APEXDRV_TAG);
                }
            }
        }
    }
    ZwClose(file);
    if (!NT_SUCCESS(status)) *sizeOut = 0;
    return status;
}

// v10: MapStatus is a STEP NUMBER, not an NTSTATUS.  A status told us 193 eleven times and never
// which line produced it; a step names the line.  The NTSTATUS goes to ResultStatus instead.
#define APEXDRV_MAP_STEP_READ     1   // open / size / read of the file
#define APEXDRV_MAP_STEP_HEADER   2   // PE header or section-table validation
#define APEXDRV_MAP_STEP_POOL     3   // pool image allocation
#define APEXDRV_MAP_STEP_COPY     4   // section copy bounds
#define APEXDRV_MAP_STEP_ALLOC    5   // address space in the target
#define APEXDRV_MAP_STEP_RELOC    6   // relocation pass
#define APEXDRV_MAP_STEP_WRITE    7   // single image write into the target
#define APEXDRV_MAP_STEP_STUB     8   // stub page alloc / write
#define APEXDRV_MAP_STEP_IMPORTS  9   // import table (+ /GS cookie seed) in the pool image

// v11: imports are bound in the pool image before the single write, so a second pass
// over the target is never needed.  x64 only, like the rest of the mapper.
static NTSTATUS ApexdrvFindModuleBaseByName(PEPROCESS process, const char* asciiName,
                                            PVOID* baseOut) {
    KAPC_STATE  apcState;
    NTSTATUS    status = STATUS_NOT_FOUND;
    PPEB        peb;
    WCHAR       wanted[APEXDRV_MAX_MODULE_NAME_CHARS];
    SIZE_T      wantedChars = 0;
    PLIST_ENTRY head;
    PLIST_ENTRY entry;
    ULONG       guard = 0;

    if (asciiName == NULL || baseOut == NULL) return STATUS_INVALID_PARAMETER;
    *baseOut = NULL;

    while (asciiName[wantedChars] != '\0' &&
           wantedChars < APEXDRV_MAX_MODULE_NAME_CHARS - 1) {
        wanted[wantedChars] = (WCHAR)(UCHAR)asciiName[wantedChars];
        ++wantedChars;
    }
    if (wantedChars == 0) return STATUS_NOT_FOUND;
    wanted[wantedChars] = L'\0';

    peb = PsGetProcessPeb(process);
    if (peb == NULL) return STATUS_NOT_FOUND;

    KeStackAttachProcess(process, &apcState);
    __try {
        PVOID ldr = *(PVOID*)((PUCHAR)peb + APEXDRV_PEB_LDR_OFFSET);
        if (ldr != NULL) {
            head  = (PLIST_ENTRY)((PUCHAR)ldr + APEXDRV_LDR_LIST_OFFSET);
            entry = head->Flink;
            while (entry != head && guard < APEXDRV_MAX_MODULES) {
                ULONG64          base = *(ULONG64*)((PUCHAR)entry + APEXDRV_LDR_DLLBASE_OFFSET);
                PCUNICODE_STRING name =
                    (PCUNICODE_STRING)((PUCHAR)entry + APEXDRV_LDR_BASENAME_OFFSET);
                PLIST_ENTRY      next = entry->Flink;

                if (base != 0 && ApexdrvNameEquals(name, wanted, wantedChars)) {
                    *baseOut = (PVOID)(ULONG_PTR)base;
                    status = STATUS_SUCCESS;
                    break;
                }
                entry = next;
                guard++;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
    }
    KeUnstackDetachProcess(&apcState);

    return status;
}

// Resolves one export of `moduleBase` by name or ordinal.  A forwarder string
// ("KERNELBASE.Foo") names another module, so the core recurses; the entry point
// below starts at depth 0.
static NTSTATUS ApexdrvResolveExportEntryDepth(PEPROCESS process, PVOID moduleBase,
                                               const char* nameOrNull, ULONG ordinalOrZero,
                                               ULONG depth, PVOID* addressOut) {
    KAPC_STATE apcState;
    NTSTATUS   status = STATUS_PROCEDURE_NOT_FOUND;
    ULONG      rva = 0;

    if (moduleBase == NULL || addressOut == NULL) return STATUS_INVALID_PARAMETER;
    *addressOut = NULL;
    if (nameOrNull == NULL && ordinalOrZero == 0) return STATUS_INVALID_PARAMETER;

    KeStackAttachProcess(process, &apcState);
    __try {
        ULONG lfanew;
        ULONG directoryRva;
        ULONG directorySize;
        ULONG numberOfFunctions;
        ULONG functionsRva;
        ULONG index;
        PVOID optionalHeader;

        if (*(USHORT*)((PUCHAR)moduleBase) != 0x5A4D) {                   // 'MZ'
            status = STATUS_INVALID_IMAGE_FORMAT;
        } else {
            lfanew = *(ULONG*)((PUCHAR)moduleBase + 0x3C);
            if (*(ULONG*)((PUCHAR)moduleBase + lfanew) != 0x00004550) {  // 'PE\0\0'
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else {
                optionalHeader = (PUCHAR)moduleBase + lfanew + 0x18;
                if (*(USHORT*)optionalHeader != 0x020B) {                // PE32+ only
                    status = STATUS_INVALID_IMAGE_FORMAT;
                } else {
                    directoryRva  = *(ULONG*)((PUCHAR)optionalHeader + 0x70);
                    directorySize = *(ULONG*)((PUCHAR)optionalHeader + 0x74);
                    if (directoryRva == 0 || directorySize == 0) {
                        status = STATUS_PROCEDURE_NOT_FOUND;
                    } else {
                        numberOfFunctions = *(ULONG*)((PUCHAR)moduleBase + directoryRva + 0x14);
                        functionsRva      = *(ULONG*)((PUCHAR)moduleBase + directoryRva + 0x1C);

                        if (nameOrNull != NULL) {
                            ULONG numberOfNames =
                                *(ULONG*)((PUCHAR)moduleBase + directoryRva + 0x18);
                            ULONG namesRva    =
                                *(ULONG*)((PUCHAR)moduleBase + directoryRva + 0x20);
                            ULONG ordinalsRva =
                                *(ULONG*)((PUCHAR)moduleBase + directoryRva + 0x24);

                            if (numberOfNames > APEXDRV_MAX_EXPORT_NAMES) {
                                status = STATUS_INVALID_IMAGE_FORMAT;
                            } else {
                                for (index = 0; index < numberOfNames; ++index) {
                                    ULONG       nameRva =
                                        *(ULONG*)((PUCHAR)moduleBase + namesRva + index * 4);
                                    const char* text =
                                        (const char*)((PUCHAR)moduleBase + nameRva);

                                    if (ApexdrvAsciiEquals(text, nameOrNull)) {
                                        ULONG ordinal = (ULONG)*(USHORT*)(
                                            (PUCHAR)moduleBase + ordinalsRva + index * 2);
                                        if (ordinal < numberOfFunctions) {
                                            rva = *(ULONG*)((PUCHAR)moduleBase +
                                                            functionsRva + ordinal * 4);
                                        }
                                        break;
                                    }
                                }
                            }
                        } else {
                            ULONG ordinalBase =
                                *(ULONG*)((PUCHAR)moduleBase + directoryRva + 0x10);
                            index = ordinalOrZero - ordinalBase;
                            if (ordinalOrZero >= ordinalBase && index < numberOfFunctions) {
                                rva = *(ULONG*)((PUCHAR)moduleBase + functionsRva + index * 4);
                            }
                        }

                        // A forwarder is an ASCII string inside the export directory
                        // itself, never a real RVA elsewhere in the image.
                        if (rva != 0) {
                            if (rva >= directoryRva &&
                                (ULONG64)rva < (ULONG64)directoryRva + directorySize &&
                                depth < APEXDRV_MAX_FORWARDER_DEPTH) {
                                const char* text = (const char*)((PUCHAR)moduleBase + rva);
                                char        dll[APEXDRV_MAX_MODULE_NAME_CHARS];
                                char        function[APEXDRV_MAX_MODULE_NAME_CHARS];
                                ULONG       at = 0;
                                ULONG       dllChars = 0;
                                ULONG       chars = 0;
                                PVOID       forwardBase = NULL;
                                BOOLEAN     forwarded = FALSE;

                                while (text[at] != '\0' && text[at] != '.' &&
                                       dllChars < sizeof(dll) - 1) {
                                    dll[dllChars++] = text[at];
                                    ++at;
                                }
                                dll[dllChars] = '\0';
                                if (text[at] == '.') {
                                    ++at;
                                    while (text[at] != '\0' &&
                                           chars < sizeof(function) - 1) {
                                        function[chars++] = text[at];
                                        ++at;
                                    }
                                }
                                function[chars] = '\0';

                                // a forwarder names the module without its extension
                                if (chars != 0 && dllChars >= 4) {
                                    if ((dll[dllChars - 4] | 32) != '.' ||
                                        (dll[dllChars - 3] | 32) != 'd' ||
                                        (dll[dllChars - 2] | 32) != 'l' ||
                                        (dll[dllChars - 1] | 32) != 'l') {
                                        if (dllChars + 4 < sizeof(dll)) {
                                            dll[dllChars++] = '.';
                                            dll[dllChars++] = 'd';
                                            dll[dllChars++] = 'l';
                                            dll[dllChars++] = 'l';
                                            dll[dllChars]   = '\0';
                                        }
                                    }
                                }

                                if (NT_SUCCESS(ApexdrvFindModuleBaseByName(process, dll,
                                                                          &forwardBase)) &&
                                    forwardBase != NULL) {
                                    forwarded = TRUE;
                                    if (function[0] == '#') {
                                        ULONG forwardedOrdinal = 0;
                                        const char* digits = function + 1;
                                        while (*digits >= '0' && *digits <= '9') {
                                            forwardedOrdinal = forwardedOrdinal * 10 +
                                                               (ULONG)(*digits - '0');
                                            ++digits;
                                        }
                                        status = ApexdrvResolveExportEntryDepth(
                                            process, forwardBase, NULL, forwardedOrdinal,
                                            depth + 1, addressOut);
                                    } else if (function[0] != '\0') {
                                        status = ApexdrvResolveExportEntryDepth(
                                            process, forwardBase, function, 0,
                                            depth + 1, addressOut);
                                    } else {
                                        forwarded = FALSE;
                                    }
                                } else {
                                    status = STATUS_DLL_NOT_FOUND;
                                }
                                if (!forwarded && status != STATUS_DLL_NOT_FOUND) {
                                    status = STATUS_PROCEDURE_NOT_FOUND;
                                }
                            } else {
                                *addressOut = (PVOID)((PUCHAR)moduleBase + rva);
                                status = STATUS_SUCCESS;
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

static NTSTATUS ApexdrvResolveExportEntry(PEPROCESS process, PVOID moduleBase,
                                          const char* nameOrNull, ULONG ordinalOrZero,
                                          PVOID* addressOut) {
    return ApexdrvResolveExportEntryDepth(process, moduleBase, nameOrNull, ordinalOrZero,
                                          0, addressOut);
}

// Records the first failed import as "dll!name" or "dll!#N" into the 64-byte slot.
static VOID ApexdrvRecordUnresolved(PAPEXDRV_INJECT_REQUEST request, const char* dll,
                                    const char* nameOrNull, ULONG ordinal) {
    ULONG at = 0;
    ULONG index;

    for (index = 0; dll != NULL && dll[index] != '\0' &&
                    at < sizeof(request->MapUnresolvedName) - 1; ++index) {
        request->MapUnresolvedName[at++] = dll[index];
    }
    if (at < sizeof(request->MapUnresolvedName) - 1) {
        request->MapUnresolvedName[at++] = '!';
    }
    if (nameOrNull != NULL) {
        for (index = 0; nameOrNull[index] != '\0' &&
                        at < sizeof(request->MapUnresolvedName) - 1; ++index) {
            request->MapUnresolvedName[at++] = nameOrNull[index];
        }
    } else if (at < sizeof(request->MapUnresolvedName) - 1) {
        CHAR  reversed[8];
        ULONG digits = 0;

        request->MapUnresolvedName[at++] = '#';
        if (ordinal == 0) reversed[digits++] = '0';
        while (ordinal != 0 && digits < sizeof(reversed)) {
            reversed[digits++] = (CHAR)('0' + (ordinal % 10));
            ordinal /= 10;
        }
        while (digits != 0 && at < sizeof(request->MapUnresolvedName) - 1) {
            request->MapUnresolvedName[at++] = reversed[--digits];
        }
    }
    request->MapUnresolvedName[at] = '\0';
}

// Binds the import table of the pool image to the modules already loaded in the
// target.  Runs before the single write, so nothing here touches the target image.
// The first failure is named and stops the walk; the caller still writes and enters.
static NTSTATUS ApexdrvPatchImports(PEPROCESS process, PUCHAR image, ULONG imageSize,
                                    PAPEXDRV_INJECT_REQUEST request) {
    PVOID optionalHeader;
    ULONG lfanew;
    ULONG directoryRva;
    ULONG directorySize;
    ULONG at;

    if (imageSize < 0x100) return STATUS_INVALID_IMAGE_FORMAT;
    lfanew = *(ULONG*)(image + 0x3C);
    if (lfanew > imageSize || imageSize - lfanew < 0x18 + 0xC8) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    optionalHeader = image + lfanew + 0x18;
    if (*(USHORT*)optionalHeader != 0x020B) return STATUS_INVALID_IMAGE_FORMAT;

    directoryRva  = *(ULONG*)((PUCHAR)optionalHeader + 0x78);   // import, index 1
    directorySize = *(ULONG*)((PUCHAR)optionalHeader + 0x7C);
    if (directoryRva == 0 || directorySize == 0) return STATUS_SUCCESS;
    if ((ULONG64)directoryRva + directorySize > imageSize) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }

    request->MapStatus = APEXDRV_MAP_STEP_IMPORTS;

    for (at = 0; at + 20 <= directorySize; at += 20) {
        PUCHAR  descriptor = image + directoryRva + at;
        ULONG   nameRva    = *(ULONG*)(descriptor + 0x0C);
        ULONG   oftRva     = *(ULONG*)(descriptor + 0x00);
        ULONG   ftRva      = *(ULONG*)(descriptor + 0x10);
        char    dll[APEXDRV_MAX_MODULE_NAME_CHARS];
        ULONG   dllChars   = 0;
        ULONG   thunkRva;
        ULONG   thunks;
        ULONG   i;
        BOOLEAN haveModule = FALSE;
        PVOID   moduleBase = NULL;

        if (nameRva == 0 && ftRva == 0) break;      // all-zero terminator
        if (nameRva == 0) continue;                 // nothing to name a failure after

        if (nameRva < imageSize) {
            while (nameRva + dllChars < imageSize &&
                   image[nameRva + dllChars] != '\0' &&
                   dllChars < sizeof(dll) - 1) {
                dll[dllChars] = (char)image[nameRva + dllChars];
                ++dllChars;
            }
        }
        dll[dllChars] = '\0';

        thunkRva = (oftRva != 0) ? oftRva : ftRva;
        if (thunkRva == 0 || thunkRva >= imageSize ||
            ftRva == 0 || ftRva >= imageSize) {
            ApexdrvRecordUnresolved(request, dll, NULL, 0);
            request->ResultStatus = STATUS_INVALID_IMAGE_FORMAT;
            return STATUS_INVALID_IMAGE_FORMAT;
        }
        thunks = (imageSize - thunkRva) / sizeof(ULONG64);

        for (i = 0; i < thunks; ++i) {
            ULONG64     thunk   = *(ULONG64*)(image + thunkRva + i * 8);
            char        nameBuf[APEXDRV_MAX_MODULE_NAME_CHARS];
            const char* name    = NULL;
            ULONG       ordinal = 0;
            PVOID       address = NULL;
            NTSTATUS    status;

            if (thunk == 0) break;                  // end of this thunk array
            if (ftRva + i * 8 + 8 > imageSize) {
                ApexdrvRecordUnresolved(request, dll, NULL, 0);
                request->ResultStatus = STATUS_INVALID_IMAGE_FORMAT;
                return STATUS_INVALID_IMAGE_FORMAT;
            }

            if ((thunk & 0x8000000000000000ULL) != 0) {
                ordinal = (ULONG)(thunk & 0xFFFF);
            } else {
                ULONG hintRva = (ULONG)thunk;
                ULONG chars   = 0;

                if (hintRva + 2 < imageSize) {
                    hintRva += 2;                   // skip the hint word
                    while (hintRva + chars < imageSize &&
                           image[hintRva + chars] != '\0' &&
                           chars < sizeof(nameBuf) - 1) {
                        nameBuf[chars] = (char)image[hintRva + chars];
                        ++chars;
                    }
                }
                nameBuf[chars] = '\0';
                name = nameBuf;
            }

            if (!haveModule) {
                status = ApexdrvFindModuleBaseByName(process, dll, &moduleBase);
                if (!NT_SUCCESS(status) || moduleBase == NULL) {
                    ApexdrvRecordUnresolved(request, dll, name, ordinal);
                    request->ResultStatus = STATUS_DLL_NOT_FOUND;
                    return STATUS_DLL_NOT_FOUND;
                }
                haveModule = TRUE;
            }

            status = ApexdrvResolveExportEntry(process, moduleBase, name, ordinal, &address);
            if (!NT_SUCCESS(status) || address == NULL) {
                ApexdrvRecordUnresolved(request, dll, name, ordinal);
                request->ResultStatus = STATUS_PROCEDURE_NOT_FOUND;
                return STATUS_PROCEDURE_NOT_FOUND;
            }

            *(ULONG64*)(image + ftRva + i * 8) = (ULONG64)(ULONG_PTR)address;
            ++request->MapImportCount;
        }
    }

    return STATUS_SUCCESS;
}

// Map an image file into the target.  Every step that can fail writes its NTSTATUS to
// MapStatus so the verdict never has to guess which stage refused.  The image is built
// entirely in pool and written ONCE, so the target never sees a half-mapped picture.
static NTSTATUS ApexdrvManualMap(PEPROCESS process, HANDLE processHandle, PCWSTR path,
                                 PAPEXDRV_INJECT_REQUEST request,
                                 PVOID* remoteBaseOut, ULONG* entryRvaOut) {
    PUCHAR          file = NULL;
    ULONG           fileSize = 0;
    PUCHAR          image = NULL;
    ULONG           imageSize = 0;
    ULONG           headersSize = 0;
    ULONG           sectionCount = 0;
    ULONG           entryRva = 0;
    ULONG           relocRva = 0;
    ULONG           relocSize = 0;
    ULONG64         preferredBase = 0;
    ULONG64         actualBase = 0;
    ULONG64         delta = 0;
    SIZE_T          regionSize;
    PUCHAR          nt = NULL;
    PAPEXDRV_SECTION_HEADER sections = NULL;
    ULONG           i;
    NTSTATUS        status;

    *remoteBaseOut = NULL;
    *entryRvaOut   = 0;
    request->MapStatus = 0;

    status = ApexdrvReadImageFile(path, (PVOID*)&file, &fileSize);
    if (!NT_SUCCESS(status)) {
        request->MapStatus = APEXDRV_MAP_STEP_READ;
        request->ResultStatus = status;
        return status;
    }

    // --- header sanity.  Anything unexpected stops here with a named status. ---
    if (fileSize < 0x100 || *(USHORT*)file != 0x5A4D) status = STATUS_INVALID_IMAGE_FORMAT;
    else {
        ULONG lfanew = *(ULONG*)(file + 0x3C);
        if (lfanew + 0x100 > fileSize || *(ULONG*)(file + lfanew) != 0x00004550) {
            status = STATUS_INVALID_IMAGE_FORMAT;
        } else {
            nt = file + lfanew + 4;                    // IMAGE_FILE_HEADER
            sectionCount   = *(USHORT*)(nt + 2);
            headersSize    = *(ULONG*)(nt + 20 + 0x3C); // SizeOfHeaders
            imageSize      = *(ULONG*)(nt + 20 + 0x38); // SizeOfImage
            preferredBase  = *(ULONG64*)(nt + 20 + 0x18);
            entryRva       = *(ULONG*)(nt + 20 + 0x10);
            relocRva       = *(ULONG*)(nt + 20 + 0x98);
            relocSize      = *(ULONG*)(nt + 20 + 0x9C);
            if (*(USHORT*)nt != 0x8664 || *(USHORT*)(nt + 20) != 0x20B) {
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else if (sectionCount == 0 || sectionCount > APEXDRV_IMAGE_MAX_SECTIONS) {
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else if (imageSize < headersSize || imageSize > APEXDRV_IMAGE_MAX_BYTES) {
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else if (entryRva == 0 || entryRva >= imageSize) {
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else if (headersSize > fileSize) {
                status = STATUS_INVALID_IMAGE_FORMAT;
            } else {
                sections = (PAPEXDRV_SECTION_HEADER)(nt + 20 + *(USHORT*)(nt + 16));
                if ((PUCHAR)(sections + sectionCount) > file + fileSize) {
                    status = STATUS_INVALID_IMAGE_FORMAT;
                }
            }
        }
    }
    if (!NT_SUCCESS(status)) {
        ExFreePoolWithTag(file, APEXDRV_TAG);
        request->MapStatus = APEXDRV_MAP_STEP_HEADER;
        request->ResultStatus = status;
        return status;
    }

    // --- build the image in pool: headers, then every section at its RVA ---
    image = (PUCHAR)ExAllocatePoolWithTag(PagedPool, imageSize, APEXDRV_TAG);
    if (image == NULL) {
        ExFreePoolWithTag(file, APEXDRV_TAG);
        request->MapStatus = APEXDRV_MAP_STEP_POOL;
        request->ResultStatus = STATUS_INSUFFICIENT_RESOURCES;
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    RtlZeroMemory(image, imageSize);
    RtlCopyMemory(image, file, headersSize);
    for (i = 0; i < sectionCount; ++i) {
        ULONG va  = sections[i].VirtualAddress;
        ULONG raw = sections[i].SizeOfRawData;
        ULONG ptr = sections[i].PointerToRawData;
        ULONG n;
        if (va >= imageSize || raw == 0) continue;
        n = raw;
        if (n > imageSize - va) n = imageSize - va;
        if (ptr + n > fileSize) {
            status = STATUS_INVALID_IMAGE_FORMAT;
            break;
        }
        RtlCopyMemory(image + va, file + ptr, n);
    }
    ExFreePoolWithTag(file, APEXDRV_TAG);
    if (!NT_SUCCESS(status)) {
        ExFreePoolWithTag(image, APEXDRV_TAG);
        request->MapStatus = APEXDRV_MAP_STEP_COPY;
        request->ResultStatus = status;
        return status;
    }

    // --- allocate: preferred base first, anywhere plausible otherwise ---
    {
        PVOID base = (PVOID)(ULONG_PTR)preferredBase;
        regionSize = imageSize;
        status = ZwAllocateVirtualMemory(processHandle, &base, 0, &regionSize,
                                         MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
        if (!NT_SUCCESS(status)) {
            base = NULL;
            regionSize = imageSize;
            status = ZwAllocateVirtualMemory(processHandle, &base, 0, &regionSize,
                                             MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
        }
        if (!NT_SUCCESS(status)) {
            ExFreePoolWithTag(image, APEXDRV_TAG);
            request->MapStatus = APEXDRV_MAP_STEP_ALLOC;
            request->ResultStatus = status;
            return status;
        }
        actualBase = (ULONG64)(ULONG_PTR)base;
        delta = actualBase - preferredBase;
    }
    request->MapBase = actualBase;

    // --- relocations, in the pool image before the single write ---
    if (delta != 0 && relocRva != 0 && relocSize != 0) {
        ULONG at = 0;
        while (at + 8 <= relocSize && relocRva + at + 8 <= imageSize) {
            PUCHAR block = image + relocRva + at;
            ULONG  pageRva  = *(ULONG*)block;
            ULONG  blockSize = *(ULONG*)(block + 4);
            ULONG  e;
            if (blockSize < 8 || at + blockSize > relocSize) break;
            for (e = 8; e + 2 <= blockSize; e += 2) {
                USHORT entry = *(USHORT*)(block + e);
                ULONG  type  = entry >> 12;
                ULONG  off   = entry & 0x0FFF;
                if (type == 10 /* DIR64 */ && pageRva + off + 8 <= imageSize) {
                    *(ULONG64*)(image + pageRva + off) += delta;
                    ++request->MapRelocCount;
                }
            }
            at += blockSize;
        }
    }

    // --- /GS cookie seed and imports, still in the pool image ---
    {
        PUCHAR opt         = image + *(ULONG*)(image + 0x3C) + 0x18;
        ULONG  loadCfgRva  = *(ULONG*)(opt + 0xC0);         // load config, index 10
        ULONG  loadCfgSize = *(ULONG*)(opt + 0xC4);

        // The cookie field holds a VA of the linked image; the reloc pass already
        // added the delta to it when the image moved, so actualBase is the base here.
        if (loadCfgRva != 0 && loadCfgSize >= 0x60 &&
            (ULONG64)loadCfgRva + 0x60 <= imageSize) {
            ULONG64 cookieVa  = *(ULONG64*)(image + loadCfgRva + 0x58);
            ULONG64 cookieRva = cookieVa - actualBase;
            if (cookieVa != 0 && cookieRva != 0 && cookieRva + 8 <= imageSize) {
                *(ULONG64*)(image + (ULONG)cookieRva) = 0x00002B992DDFA232ULL ^ actualBase;
            }
        }

        // A failed import does not return: the write and the entry call still run,
        // so the run measures.  MapStatus/MapUnresolvedName keep the failure; the
        // caller resets ResultStatus once the delivery itself succeeds.
        ApexdrvPatchImports(process, image, imageSize, request);
        // v13: a CLEAN import pass must not leave the IMPORTS step behind.  Before
        // this, MapStatus stayed 9 after every successful pass (the step was set on
        // entry to PatchImports and only a failure overwrote anything), so a delivered
        // run read as if a step had refused when none had.  0 = no step refused; 9
        // now means exactly "an import did not resolve" (MapUnresolvedName names it).
        if (request->MapUnresolvedName[0] == '\0') {
            request->MapStatus = 0;
        }
    }

    status = ApexdrvWriteProcessMemory(process, (PVOID)(ULONG_PTR)actualBase, image, imageSize);
    ExFreePoolWithTag(image, APEXDRV_TAG);
    if (!NT_SUCCESS(status)) {
        SIZE_T freeSize = 0;
        ZwFreeVirtualMemory(processHandle, (PVOID*)&actualBase, &freeSize, MEM_RELEASE);
        request->MapBase = 0;
        request->MapStatus = APEXDRV_MAP_STEP_WRITE;
        request->ResultStatus = status;
        return status;
    }

    *remoteBaseOut = (PVOID)(ULONG_PTR)actualBase;
    *entryRvaOut   = entryRva;
    return STATUS_SUCCESS;
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
    PVOID               contextArg  = NULL;     // APC NormalContext -> RCX
    BOOLEAN             manualMap   = (BOOLEAN)((request->Flags & APEXDRV_FLAG_MANUAL_MAP) != 0);
    PVOID               mapBase     = NULL;
    ULONG               mapEntryRva = 0;

    if (request->ProcessId == 0) return STATUS_INVALID_PARAMETER;
    if (request->ThreadId == 0)  return STATUS_INVALID_PARAMETER;
    if (request->LoadLibraryAddress == 0 && manualMap == FALSE &&
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
    request->StubBase             = 0;
    request->StubEntered          = 0;
    request->StubRcx              = 0;
    request->ResolvedExLoader     = 0;
    request->MapBase              = 0;
    request->MapEntryResult       = 0;
    request->MapEntryFlag         = 0;
    request->MapStatus            = 0;
    request->MapRelocCount        = 0;
    request->MapImportCount       = 0;
    request->MapUnresolvedName[0] = '\0';
    request->MapTlsUsed           = 0;

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
        const BOOLEAN exLoader = (request->Flags & APEXDRV_FLAG_EX_LOADER) != 0;
        status = ApexdrvResolveExportRva(process, targetInfo.KernelBaseBase,
                                         exLoader ? "LoadLibraryExW" : "LoadLibraryW",
                                         &exportRva);
        if (!NT_SUCCESS(status)) {
            request->ResultStatus = status;
            ZwClose(processHandle);
            ObDereferenceObject(process);
            return status;
        }
        loadLibrary = targetInfo.KernelBaseBase + exportRva;
        request->ResolvePath = 1;
        request->ResolvedExLoader = exLoader ? 1 : 0;
    }
    request->ResolvedLoadLibrary = loadLibrary;

    // v9: map the image instead of asking a loader for it.  Nothing after this
    // point needs kernelbase, so the resolve above may be absent.
    if (manualMap) {
        status = ApexdrvManualMap(process, processHandle, request->DllPath, request,
                                  &mapBase, &mapEntryRva);
        if (!NT_SUCCESS(status)) {
            request->ResultStatus = status;
            ZwClose(processHandle);
            ObDereferenceObject(process);
            return status;
        }
        request->ResolvedLoadLibrary = (ULONG64)(ULONG_PTR)mapBase + mapEntryRva;
    }

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

    // v6: an instrumented stub as the entry, when asked for.  v9 reuses the same
    // slot for the map stub, which calls the mapped entry instead of a loader.
    if (request->Flags & APEXDRV_FLAG_STUB_ROUTINE) {
        UCHAR  stubImage[APEXDRV_STUB_TOTAL_BYTES + APEXDRV_MAP_STUB_TOTAL_BYTES];
        SIZE_T stubSize;
        PVOID  stubBuffer = NULL;

        if (manualMap) {
            stubSize = APEXDRV_MAP_STUB_TOTAL_BYTES;
            ApexdrvStampMapStub(stubImage, request->ResolvedLoadLibrary);
        } else {
            stubSize = APEXDRV_STUB_TOTAL_BYTES;
            ApexdrvStampStub(stubImage, loadLibrary,
                             (BOOLEAN)((request->Flags & APEXDRV_FLAG_EX_LOADER) != 0));
        }
        status = ZwAllocateVirtualMemory(processHandle, &stubBuffer, 0, &stubSize,
                                         MEM_COMMIT | MEM_RESERVE,
                                         PAGE_EXECUTE_READWRITE);
        if (NT_SUCCESS(status)) {
            status = ApexdrvWriteProcessMemory(process, stubBuffer, stubImage, stubSize);
        }
        if (!NT_SUCCESS(status)) {
            if (stubBuffer != NULL) {
                SIZE_T freeSize = 0;
                ZwFreeVirtualMemory(processHandle, &stubBuffer, &freeSize, MEM_RELEASE);
            }
            request->MapStatus   = APEXDRV_MAP_STEP_STUB;
            request->ResultStatus = status;
            ZwClose(processHandle);
            ObDereferenceObject(process);
            return status;
        }
        request->StubBase = (ULONG64)(ULONG_PTR)stubBuffer;
        loadLibrary      = (ULONG64)(ULONG_PTR)stubBuffer;
        // map mode hands the image base to the routine as RCX; the loader route
        // keeps the path there and the entry is the helper function.
        contextArg = manualMap ? mapBase : remoteBuffer;
    } else {
        contextArg = remoteBuffer;
    }

    // Queue LoadLibraryW(remotePath) on the caller's thread instead of creating
    // one: see the block comment above ApexdrvQueueLoaderApc for why.
    status = ApexdrvQueueLoaderApc(process, request->ThreadId, contextArg,
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
        // v13 note, measured cost not a defect: the mapped image and the stub page
        // stay too - the APC is armed and may still deliver later, so freeing either
        // would fault the target when it does.  Each undelivered retry costs about
        // imageSize + one page (apxprobe: ~0x3000 + 0x1000) and the launcher tries
        // up to 6 threads per inject; the entry poll now breaks on the DONE flag, so
        // a returning entry no longer burns the 10 s window either.
        request->StatusEchoAfter = ApexdrvReadProcessMemory(
            process, remoteBuffer, request->RemotePathEchoAfter,
            pathBytes < sizeof(request->RemotePathEchoAfter)
                ? pathBytes
                : sizeof(request->RemotePathEchoAfter) - sizeof(WCHAR));
        request->RemotePathEchoAfter[APEXDRV_MAX_PATH_CHARS - 1] = L'\0';
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
    request->RemotePathEchoAfter[APEXDRV_MAX_PATH_CHARS - 1] = L'\0';

    delay.QuadPart = -800 * 10000;                 // + 800 ms = 1 s after delivery
    KeDelayExecutionThread(KernelMode, FALSE, &delay);

    // v6: read the stub's stamps back.  StubEntered rules out "no user code ran at all";
    // StubRcx says what the routine actually received, compared against RemoteBase.
    // The read starts at the DATA slot, not at the stub base: the loader stub's magic is
    // at +38 and its captured RCX at +46 (0..37 are code); the map stub's four slots sit
    // at +64/+72/+80/+88 behind 64 bytes of code (v13 layout, see ApexdrvStampMapStub).
    if (request->StubBase != 0 && manualMap) {
        // Map mode: the entry call has to finish before the result slot means
        // anything, so poll for it instead of sampling once.  v13: the stub stamps
        // APEXDRV_MAP_STUB_DONE after storing RAX, so the poll breaks on the FLAG -
        // "DllMain returned FALSE" (flag set, result 0) and "DllMain never returned"
        // (flag 0 after the full window) are different verdicts, and a FALSE return
        // no longer burns the whole 10 s waiting for a nonzero RAX that never comes.
        ULONG64 mapStamp[4] = { 0, 0, 0, 0 };
        for (i = 0; i < 100; i++) {                 // 100 x 100 ms = 10 s cap
            if (NT_SUCCESS(ApexdrvReadProcessMemory(
                    process,
                    (PVOID)(ULONG_PTR)(request->StubBase + APEXDRV_MAP_STUB_CODE_BYTES),
                    mapStamp, sizeof(mapStamp)))) {
                request->StubEntered    = (ULONG)mapStamp[0];
                request->StubRcx        = mapStamp[1];
                request->MapEntryResult = mapStamp[2];
                request->MapEntryFlag   = (ULONG)mapStamp[3];
                if (mapStamp[3] != 0) break;       // DONE: the entry RETURNED
            }
            delay.QuadPart = -100 * 10000;          // 100 ms
            KeDelayExecutionThread(KernelMode, FALSE, &delay);
        }
    } else if (request->StubBase != 0) {
        ULONG64 stamp[2] = { 0, 0 };
        if (NT_SUCCESS(ApexdrvReadProcessMemory(process,
                                                (PVOID)(ULONG_PTR)(request->StubBase +
                                                                   APEXDRV_STUB_CODE_BYTES),
                                                stamp, sizeof(stamp)))) {
            request->StubEntered = (ULONG)stamp[0];
            request->StubRcx     = stamp[1];
        }
    }


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
                NTSTATUS injectStatus = ApexdrvInject(
                    (PAPEXDRV_INJECT_REQUEST)irp->AssociatedIrp.SystemBuffer);
                // v11: a failed status makes METHOD_BUFFERED skip the copy-back - h283 measured
                // the whole out block reading back as zeros, step and module count included.  The
                // IRP therefore completes as SUCCESS and the real NTSTATUS rides in ResultStatus;
                // a "failed" rung is then a readable out block instead of a bare Win32 code.
                status      = NT_SUCCESS(injectStatus) ? injectStatus : STATUS_SUCCESS;
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
