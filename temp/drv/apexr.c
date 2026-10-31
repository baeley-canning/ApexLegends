/* apexr.c -- minimal kernel reader for a process whose PROCESS_VM_READ right
 * EAC's Ob callback strips (r5apex_dx12).  Two IOCTLs:
 *
 *   IOCTL_APEXR_READ  (0x800, METHOD_BUFFERED)
 *     in : { ULONG Pid; ULONG Size; ULONG64 Address; }
 *     out: Size bytes, Information = bytes copied
 *     -> MmCopyVirtualMemory from the target process into the system buffer.
 *
 *   IOCTL_APEXR_QUERY (0x801, METHOD_BUFFERED)
 *     in : { ULONG Pid; ULONG Pad; ULONG64 Address; }
 *     out: { Base, AllocationBase, AllocationProtect, PartitionId,
 *            RegionSize, State, Protect, Type }
 *     -> attach + ZwQueryVirtualMemory(MemoryBasicInformation), so the user
 *        mode side can walk VADs without PROCESS_QUERY_INFORMATION.
 */
#include <ntifs.h>

#define APEXR_DEVICE  L"\\Device\\apexr"
#define APEXR_SYMLINK L"\\DosDevices\\apexr"

#define IOCTL_APEXR_READ  CTL_CODE(FILE_DEVICE_UNKNOWN, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_APEXR_QUERY CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)

typedef struct _APEXR_READ_REQ {
    ULONG Pid;
    ULONG Size;
    ULONG64 Address;
} APEXR_READ_REQ, *PAPEXR_READ_REQ;

typedef struct _APEXR_QUERY_REQ {
    ULONG Pid;
    ULONG Pad;
    ULONG64 Address;
} APEXR_QUERY_REQ, *PAPEXR_QUERY_REQ;

typedef struct _APEXR_QUERY_RSP {
    ULONG64 BaseAddress;
    ULONG64 AllocationBase;
    ULONG AllocationProtect;
    ULONG PartitionId;
    ULONG64 RegionSize;
    ULONG State;
    ULONG Protect;
    ULONG Type;
    ULONG Spare;
} APEXR_QUERY_RSP, *PAPEXR_QUERY_RSP;

static NTSTATUS ApexrRead(PVOID in, ULONG inLen, PVOID out, ULONG outLen, PULONG info)
{
    APEXR_READ_REQ req;
    PEPROCESS proc = NULL;
    NTSTATUS status;
    SIZE_T copied = 0;

    if (inLen < sizeof(APEXR_READ_REQ)) return STATUS_INVALID_PARAMETER;
    RtlCopyMemory(&req, in, sizeof(req));          /* in == out for buffered IO */
    if (req.Size == 0 || req.Size > outLen) return STATUS_BUFFER_TOO_SMALL;

    status = PsLookupProcessByProcessId((HANDLE)(ULONG_PTR)req.Pid, &proc);
    if (!NT_SUCCESS(status)) return status;

    status = MmCopyVirtualMemory(proc, (PVOID)(ULONG_PTR)req.Address,
                                 PsGetCurrentProcess(), out, req.Size,
                                 KernelMode, &copied);
    ObDereferenceObject(proc);
    *info = (ULONG)copied;
    return status;
}

static NTSTATUS ApexrQuery(PVOID in, ULONG inLen, PVOID out, ULONG outLen, PULONG info)
{
    APEXR_QUERY_REQ req;
    PAPEXR_QUERY_RSP rsp = (PAPEXR_QUERY_RSP)out;
    MEMORY_BASIC_INFORMATION mbi;
    PEPROCESS proc = NULL;
    KAPC_STATE apc;
    NTSTATUS status;
    SIZE_T ret = 0;

    if (inLen < sizeof(APEXR_QUERY_REQ) || outLen < sizeof(APEXR_QUERY_RSP))
        return STATUS_INVALID_PARAMETER;
    RtlCopyMemory(&req, in, sizeof(req));

    status = PsLookupProcessByProcessId((HANDLE)(ULONG_PTR)req.Pid, &proc);
    if (!NT_SUCCESS(status)) return status;

    KeStackAttachProcess((PRKPROCESS)proc, &apc);
    status = ZwQueryVirtualMemory(NtCurrentProcess(), (PVOID)(ULONG_PTR)req.Address,
                                  MemoryBasicInformation, &mbi, sizeof(mbi), &ret);
    KeUnstackDetachProcess(&apc);
    ObDereferenceObject(proc);

    if (NT_SUCCESS(status)) {
        rsp->BaseAddress = (ULONG64)(ULONG_PTR)mbi.BaseAddress;
        rsp->AllocationBase = (ULONG64)(ULONG_PTR)mbi.AllocationBase;
        rsp->AllocationProtect = mbi.AllocationProtect;
        rsp->RegionSize = (ULONG64)mbi.RegionSize;
        rsp->State = mbi.State;
        rsp->Protect = mbi.Protect;
        rsp->Type = mbi.Type;
        *info = sizeof(APEXR_QUERY_RSP);
    }
    return status;
}

static NTSTATUS ApexrDispatch(PDEVICE_OBJECT dev, PIRP irp)
{
    PIO_STACK_LOCATION sp = IoGetCurrentIrpStackLocation(irp);
    NTSTATUS status = STATUS_SUCCESS;
    ULONG info = 0;
    PVOID buf = irp->AssociatedIrp.SystemBuffer;
    ULONG inLen = sp->Parameters.DeviceIoControl.InputBufferLength;
    ULONG outLen = sp->Parameters.DeviceIoControl.OutputBufferLength;

    UNREFERENCED_PARAMETER(dev);

    switch (sp->MajorFunction) {
    case IRP_MJ_CREATE:
    case IRP_MJ_CLOSE:
    case IRP_MJ_CLEANUP:
        break;
    case IRP_MJ_DEVICE_CONTROL:
        switch (sp->Parameters.DeviceIoControl.IoControlCode) {
        case IOCTL_APEXR_READ:
            status = ApexrRead(buf, inLen, buf, outLen, &info);
            break;
        case IOCTL_APEXR_QUERY:
            status = ApexrQuery(buf, inLen, buf, outLen, &info);
            break;
        default:
            status = STATUS_INVALID_DEVICE_REQUEST;
            break;
        }
        break;
    default:
        status = STATUS_INVALID_DEVICE_REQUEST;
        break;
    }

    irp->IoStatus.Status = status;
    irp->IoStatus.Information = info;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}

static VOID ApexrUnload(PDRIVER_OBJECT drv)
{
    UNICODE_STRING sym;
    UNREFERENCED_PARAMETER(drv);

    RtlInitUnicodeString(&sym, APEXR_SYMLINK);
    IoDeleteSymbolicLink(&sym);
    if (drv->DeviceObject) IoDeleteDevice(drv->DeviceObject);
}

NTSTATUS DriverEntry(PDRIVER_OBJECT drv, PUNICODE_STRING regPath)
{
    UNICODE_STRING devName, symName;
    PDEVICE_OBJECT dev = NULL;
    NTSTATUS status;
    int i;

    UNREFERENCED_PARAMETER(regPath);

    RtlInitUnicodeString(&devName, APEXR_DEVICE);
    status = IoCreateDevice(drv, 0, &devName, FILE_DEVICE_UNKNOWN, 0, FALSE, &dev);
    if (!NT_SUCCESS(status)) return status;

    RtlInitUnicodeString(&symName, APEXR_SYMLINK);
    status = IoCreateSymbolicLink(&symName, &devName);
    if (!NT_SUCCESS(status)) {
        IoDeleteDevice(dev);
        return status;
    }

    dev->Flags |= DO_BUFFERED_IO;
    dev->Flags &= ~DO_DEVICE_INITIALIZING;

    for (i = 0; i <= IRP_MJ_MAXIMUM_FUNCTION; i++)
        drv->MajorFunction[i] = ApexrDispatch;
    drv->DriverUnload = ApexrUnload;
    return STATUS_SUCCESS;
}
