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

static PFN_ZwCreateThreadEx ApexdrvResolveCreateThreadEx(void) {
    static PFN_ZwCreateThreadEx cached = NULL;
    UNICODE_STRING name;

    if (cached != NULL) return cached;

    RtlInitUnicodeString(&name, L"ZwCreateThreadEx");
    cached = (PFN_ZwCreateThreadEx)MmGetSystemRoutineAddress(&name);
    return cached;
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

#define APEXDRV_TAG                 'vpxA'   // 'Apxv'
#define APEXDRV_MAX_THREAD_WAIT_MS  5000

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
    HANDLE    threadHandle  = NULL;
    PVOID     remoteBuffer  = NULL;
    SIZE_T    regionSize    = 0;
    SIZE_T    pathBytes     = 0;
    NTSTATUS  status;
    PFN_ZwCreateThreadEx createThread;

    if (request->ProcessId == 0)          return STATUS_INVALID_PARAMETER;
    if (request->LoadLibraryAddress == 0)  return STATUS_INVALID_PARAMETER;

    // Ensure the wide path is NUL terminated inside the supplied buffer.
    request->DllPath[APEXDRV_MAX_PATH_CHARS - 1] = L'\0';
    pathBytes = (wcslen(request->DllPath) + 1) * sizeof(WCHAR);
    if (pathBytes <= sizeof(WCHAR)) return STATUS_INVALID_PARAMETER;

    createThread = ApexdrvResolveCreateThreadEx();
    if (createThread == NULL) return STATUS_PROCEDURE_NOT_FOUND;

    status = ApexdrvOpenProcess(request->ProcessId, &processHandle, &process);
    if (!NT_SUCCESS(status)) return status;

    regionSize = pathBytes;
    status = ZwAllocateVirtualMemory(processHandle, &remoteBuffer, 0, &regionSize,
                                     MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!NT_SUCCESS(status)) {
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }

    status = ApexdrvWriteProcessMemory(process, remoteBuffer,
                                       request->DllPath, pathBytes);
    if (!NT_SUCCESS(status)) {
        ZwFreeVirtualMemory(processHandle, &remoteBuffer, &regionSize, MEM_RELEASE);
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }

    // User-mode thread running kernel32!LoadLibraryW(remotePath).
    status = createThread(&threadHandle, THREAD_ALL_ACCESS, NULL, processHandle,
                          (PVOID)(ULONG_PTR)request->LoadLibraryAddress,
                          remoteBuffer, 0, 0, 0, 0, NULL);
    if (!NT_SUCCESS(status)) {
        ZwFreeVirtualMemory(processHandle, &remoteBuffer, &regionSize, MEM_RELEASE);
        ZwClose(processHandle);
        ObDereferenceObject(process);
        return status;
    }

    {
        PETHREAD threadObject = NULL;
        if (NT_SUCCESS(ObReferenceObjectByHandle(threadHandle,
                                                 THREAD_QUERY_INFORMATION,
                                                 *PsThreadType, KernelMode,
                                                 (PVOID*)&threadObject, NULL))) {
            request->ThreadId = (ULONG)(ULONG_PTR)PsGetThreadId(threadObject);
            ObDereferenceObject(threadObject);
        }
    }

    // Wait for the loader so the path buffer can safely be released.
    {
        LARGE_INTEGER timeout;
        timeout.QuadPart = -((LONGLONG)APEXDRV_MAX_THREAD_WAIT_MS * 10000);
        KeWaitForSingleObject(threadHandle, Executive, KernelMode, FALSE, &timeout);
    }

    request->RemoteBase   = (ULONG64)(ULONG_PTR)remoteBuffer;
    request->ResultStatus = STATUS_SUCCESS;

    ZwClose(threadHandle);
    ZwFreeVirtualMemory(processHandle, &remoteBuffer, &regionSize, MEM_RELEASE);
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
