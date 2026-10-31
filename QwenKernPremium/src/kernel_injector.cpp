#include "injector.h"
#include "apex_driver_ioctl.h"

#include <iostream>
#include <cstdio>
#include <cwchar>
#include <string>

#pragma comment(lib, "advapi32.lib")

// ============================================================================
// METHOD 3 — Kernel driver injection ("KERNEL" strategy)
//
// Flow (all usermode side, no handle to r5apex.exe is ever opened here):
//   1. SCM: create (or open) the demand-start kernel service "apexdrv".
//   2. Start the service  -> DriverEntry creates \Device\ApexDrv + symlink.
//   3. CreateFile("\\.\ApexDrv") and send IOCTL_APEXDRV_INJECT with
//      { PID, DLL path }.  The driver does the mapping from kernel context.
//   4. Stop + delete the service to leave as little footprint as possible.
//
// Constraints:
//   * Requires an elevated launcher (SCM create/start).
//   * The .sys must be loadable by the standard loader (signed / test signed),
//     or pre-mapped through a BYOVD loader before this runs.
// ============================================================================

namespace {

std::string LastErrorText(DWORD error) {
    char buffer[64] = { 0 };
    sprintf_s(buffer, sizeof(buffer), " (GetLastError=%lu)", error);
    return std::string(buffer);
}

std::wstring WidenAscii(const std::string& text) {
    if (text.empty()) return std::wstring();

    const int needed = MultiByteToWideChar(CP_ACP, 0, text.c_str(), -1, nullptr, 0);
    if (needed <= 1) return std::wstring();

    std::wstring wide(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(CP_ACP, 0, text.c_str(), -1, &wide[0], needed);
    wide.resize(static_cast<size_t>(needed - 1));   // drop trailing NUL
    return wide;
}

std::string NarrowAscii(const std::wstring& text) {
    if (text.empty()) return std::string();
    const int needed = WideCharToMultiByte(CP_ACP, 0, text.c_str(), -1,
                                           nullptr, 0, nullptr, nullptr);
    if (needed <= 1) return std::string();
    std::string narrow(static_cast<size_t>(needed), '\0');
    WideCharToMultiByte(CP_ACP, 0, text.c_str(), -1, &narrow[0], needed, nullptr, nullptr);
    narrow.resize(static_cast<size_t>(needed - 1));
    return narrow;
}

// CreateService/NtLoadDriver expect an NT path ("\??\C:\...\apexdrv.sys").
std::wstring ToNtPath(const std::wstring& path) {
    if (path.empty()) return path;
    if (path.rfind(L"\\??\\", 0) == 0) return path;
    if (path.rfind(L"\\\\?\\", 0) == 0) return L"\\??\\" + path.substr(4);
    return L"\\??\\" + path;
}

bool StartKernelService(SC_HANDLE scm, const std::wstring& ntDriverPath, std::string& error) {
    SC_HANDLE service = OpenServiceW(scm, APEXDRV_SERVICE_NAME,
                                     SERVICE_START | SERVICE_QUERY_STATUS |
                                     SERVICE_STOP | DELETE);
    if (!service) {
        service = CreateServiceW(scm, APEXDRV_SERVICE_NAME, APEXDRV_SERVICE_NAME,
                                 SERVICE_START | SERVICE_QUERY_STATUS | SERVICE_STOP | DELETE,
                                 SERVICE_KERNEL_DRIVER, SERVICE_DEMAND_START,
                                 SERVICE_ERROR_NORMAL, ntDriverPath.c_str(),
                                 nullptr, nullptr, nullptr, nullptr, nullptr);
        if (!service) {
            error = "CreateService(apexdrv) failed" + LastErrorText(GetLastError()) +
                    " - launcher must run elevated";
            return false;
        }
        std::cout << "[+] Kernel service created (driver: "
                  << NarrowAscii(ntDriverPath) << ")" << std::endl;
    } else {
        std::cout << "[*] Kernel service already registered, reusing it" << std::endl;
    }

    if (!StartServiceW(service, 0, nullptr)) {
        const DWORD lastError = GetLastError();
        if (lastError != ERROR_SERVICE_ALREADY_RUNNING) {
            error = "StartService(apexdrv) failed" + LastErrorText(lastError) +
                    " - unsigned drivers need test-signing or a BYOVD loader";
            CloseServiceHandle(service);
            return false;
        }
    }

    CloseServiceHandle(service);
    return true;
}

void StopAndDeleteKernelService(SC_HANDLE scm) {
    SC_HANDLE service = OpenServiceW(scm, APEXDRV_SERVICE_NAME,
                                     SERVICE_STOP | SERVICE_QUERY_STATUS | DELETE);
    if (!service) return;

    SERVICE_STATUS status{};
    ControlService(service, SERVICE_CONTROL_STOP, &status);

    // Give the I/O manager a moment to tear the device object down.
    for (int i = 0; i < 20; ++i) {
        if (!QueryServiceStatus(service, &status) ||
            status.dwCurrentState == SERVICE_STOPPED) {
            break;
        }
        Sleep(50);
    }

    DeleteService(service);
    CloseServiceHandle(service);
}

// ----------------------------------------------------------------------------
// Helpers for the kernel probe report (Q10).  Only the status values this target
// actually produces are decoded; anything else stays a raw hex code, so a new
// refusal mode shows up as a number instead of being hidden behind "-".
// ----------------------------------------------------------------------------
const char* StatusLabel(LONG status) {
    switch (static_cast<unsigned long>(status)) {
        case 0x00000000UL: return "SUCCESS";
        case 0xC0000005UL: return "ACCESS_VIOLATION";
        case 0xC0000006UL: return "IN_PAGE_ERROR";
        case 0xC0000008UL: return "INVALID_HANDLE";
        case 0xC000000DUL: return "INVALID_PARAMETER";
        case 0xC0000017UL: return "NO_MEMORY";
        case 0xC0000022UL: return "ACCESS_DENIED";
        case 0xC0000043UL: return "SHARING_VIOLATION";
        case 0xC0000101UL: return "NOT_MAPPED_VIEW";
        case 0xC000013AUL: return "CONTROL_C_EXIT";
        case 0xC0000142UL: return "DLL_INIT_FAILED";
        default:           return "";
    }
}

std::string FormatStatus(LONG status) {
    char buffer[96];
    sprintf_s(buffer, sizeof(buffer), "0x%08lX %s",
              static_cast<unsigned long>(status), StatusLabel(status));
    return std::string(buffer);
}

std::string Hex64(ULONG64 value) {
    char buffer[32];
    sprintf_s(buffer, sizeof(buffer), "%llX",
              static_cast<unsigned long long>(value));
    return std::string(buffer);
}

} // namespace

InjectionResult ApexInjector::InjectViaKernelDriver(DWORD targetPid,
                                                    const std::string& dllPath,
                                                    const std::string& driverPath) {
    InjectionResult result{};
    result.success = false;
    result.threadId = 0;
    result.dllBaseAddress = nullptr;

    if (driverPath.empty()) {
        result.errorMessage = "Kernel driver path is empty";
        return result;
    }
    if (dllPath.empty()) {
        result.errorMessage = "DLL path is empty";
        return result;
    }

    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
    if (!scm) {
        result.errorMessage = "OpenSCManager failed" + LastErrorText(GetLastError()) +
                              " - run the launcher as administrator";
        return result;
    }

    // The driver calls ZwCreateThreadEx with this user-mode entry point, so it
    // needs the LoadLibraryW address as seen inside the target.  kernel32.dll
    // is mapped at the same base across processes of a session, and the
    // export RVA is identical for the same build, so resolving it locally is
    // the standard approach.
    const ULONG64 loadLibraryAddress = reinterpret_cast<ULONG64>(
        GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryW"));
    if (loadLibraryAddress == 0) {
        result.errorMessage = "kernel32!LoadLibraryW could not be resolved";
        CloseServiceHandle(scm);
        return result;
    }

    const std::wstring ntDriverPath = ToNtPath(WidenAscii(driverPath));
    std::string serviceError;
    if (!StartKernelService(scm, ntDriverPath, serviceError)) {
        result.errorMessage = serviceError;
        CloseServiceHandle(scm);
        return result;
    }

    // The device symlink can take a fraction of a millisecond to appear.
    HANDLE hDevice = INVALID_HANDLE_VALUE;
    for (int attempt = 0; attempt < 20; ++attempt) {
        hDevice = CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE,
                              0, nullptr, OPEN_EXISTING, 0, nullptr);
        if (hDevice != INVALID_HANDLE_VALUE) break;
        Sleep(50);
    }

    if (hDevice == INVALID_HANDLE_VALUE) {
        result.errorMessage = "Could not open \\\\.\\ApexDrv" +
                              LastErrorText(GetLastError()) +
                              " - driver did not create its symlink";
        StopAndDeleteKernelService(scm);
        CloseServiceHandle(scm);
        return result;
    }

    APEXDRV_INJECT_REQUEST request{};
    request.ProcessId          = targetPid;
    request.Flags              = APEXDRV_FLAG_NONE;
    request.LoadLibraryAddress = loadLibraryAddress;
    {
        const std::wstring wideDll = WidenAscii(dllPath);
        wcsncpy_s(request.DllPath, APEXDRV_MAX_PATH_CHARS, wideDll.c_str(), _TRUNCATE);
    }

    DWORD bytesReturned = 0;
    const BOOL ioctlOk = DeviceIoControl(hDevice, IOCTL_APEXDRV_INJECT,
                                         &request, sizeof(request),
                                         &request, sizeof(request),
                                         &bytesReturned, nullptr);

    if (!ioctlOk) {
        result.errorMessage = "DeviceIoControl(IOCTL_APEXDRV_INJECT) failed" +
                              LastErrorText(GetLastError());
    } else if (request.ResultStatus != 0) {
        char statusBuffer[32] = { 0 };
        sprintf_s(statusBuffer, sizeof(statusBuffer), "0x%08lX",
                  static_cast<unsigned long>(request.ResultStatus));
        result.errorMessage = std::string("Driver reported NTSTATUS ") + statusBuffer;
    } else {
        result.success = true;
        result.threadId = request.ThreadId;
        result.dllBaseAddress = reinterpret_cast<HMODULE>(
            static_cast<ULONG_PTR>(request.RemoteBase));

        std::cout << "[+] Kernel injection SUCCESS - Thread ID: " << result.threadId
                  << ", module base: 0x" << std::hex << request.RemoteBase
                  << std::dec << std::endl;
    }

    CloseHandle(hDevice);
    StopAndDeleteKernelService(scm);   // keep the driver footprint minimal
    CloseServiceHandle(scm);
    return result;
}

// ----------------------------------------------------------------------------
// PHASE 1.4 / question Q10 — what can KERNEL context do that user mode cannot?
//
// Starts the driver, hands it the PID, and reports the NTSTATUS of every step
// the user-mode ladder needs: open with injector rights, allocate/write/free
// inside the target, and copy the target's PEB out with MmCopyVirtualMemory.
// Nothing is injected, so it is safe to run at any point - including right after
// a failed ladder.  Returns true when the driver itself answered; the per-step
// statuses are the payload, and a refused step is data, not a failed call.
// ----------------------------------------------------------------------------
bool ApexInjector::ProbeViaKernel(DWORD targetPid, const std::string& driverPath,
                                  std::string& report) {
    report.clear();
    if (driverPath.empty()) { report = "kernel driver path is empty\n"; return false; }
    if (targetPid == 0)     { report = "target PID is 0\n";              return false; }

    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
    if (!scm) {
        report = "OpenSCManager failed" + LastErrorText(GetLastError()) +
                 " - run the launcher as administrator\n";
        return false;
    }

    std::string serviceError;
    if (!StartKernelService(scm, ToNtPath(WidenAscii(driverPath)), serviceError)) {
        report = serviceError + "\n";
        CloseServiceHandle(scm);
        return false;
    }

    HANDLE device = INVALID_HANDLE_VALUE;
    for (int attempt = 0; attempt < 40; ++attempt) {
        device = CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE,
                             0, nullptr, OPEN_EXISTING, 0, nullptr);
        if (device != INVALID_HANDLE_VALUE) break;
        Sleep(25);
    }
    if (device == INVALID_HANDLE_VALUE) {
        report = "could not open \\\\.\\ApexDrv" + LastErrorText(GetLastError()) +
                 " - driver did not create its symlink\n";
        StopAndDeleteKernelService(scm);
        CloseServiceHandle(scm);
        return false;
    }

    // ABI handshake first: an older driver then fails the probe IOCTL cleanly
    // instead of misreading a longer request struct.
    APEXDRV_VERSION_INFO version{};
    DWORD bytesReturned = 0;
    if (DeviceIoControl(device, IOCTL_APEXDRV_VERSION, &version, sizeof(version),
                        &version, sizeof(version), &bytesReturned, nullptr)) {
        report += "driver ABI version " + std::to_string(version.Version) +
                  " (launcher expects " + std::to_string(APEXDRV_VERSION) + ")\n";
    } else {
        report += "IOCTL_APEXDRV_VERSION failed" + LastErrorText(GetLastError()) + "\n";
    }

    APEXDRV_PROBE_REQUEST probe{};
    probe.ProcessId = targetPid;

    bool answered = false;
    if (DeviceIoControl(device, IOCTL_APEXDRV_PROBE, &probe, sizeof(probe),
                        &probe, sizeof(probe), &bytesReturned, nullptr)) {
        answered = true;
        report += "target PID " + std::to_string(targetPid) +
                  " measured from KERNEL context:\n";
        report += "  PsLookupProcessByProcessId : " + FormatStatus(probe.StatusLookup) + "\n";
        report += "  EPROCESS->Peb              : 0x" + Hex64(probe.PebAddress) + "\n";
        report += "  ObOpenObjectByPointer(full): " + FormatStatus(probe.StatusOpen) + "\n";
        report += "  ZwAllocateVirtualMemory    : " + FormatStatus(probe.StatusAllocate) +
                  " (at 0x" + Hex64(probe.RemoteAllocation) + ")\n";
        report += "  ZwWriteVirtualMemory       : " + FormatStatus(probe.StatusWrite) + "\n";
        report += "  ZwFreeVirtualMemory        : " + FormatStatus(probe.StatusFree) + "\n";
        report += "  MmCopyVirtualMemory(PEB)   : " + FormatStatus(probe.StatusCopyVirtual) +
                  " (" + std::to_string(probe.BytesCopied) + "/" +
                  std::to_string(static_cast<unsigned>(APEXDRV_PROBE_BYTES)) + " bytes)\n";

        if (probe.BytesCopied > 0) {
            report += "  target PEB bytes           :";
            for (ULONG index = 0; index < probe.BytesCopied; ++index) {
                char byteText[8];
                sprintf_s(byteText, sizeof(byteText), " %02X",
                          static_cast<unsigned>(probe.Bytes[index]));
                report += byteText;
            }
            report += "\n";
        }

        const bool handleOk = (probe.StatusLookup == 0) && (probe.StatusOpen == 0);
        const bool allocOk  = (probe.StatusAllocate == 0);
        const bool readOk   = (probe.StatusCopyVirtual == 0) && (probe.BytesCopied > 0);

        report += std::string("verdict: kernel_handle=") + (handleOk ? "yes" : "no") +
                  "  kernel_allocation=" + (allocOk ? "yes" : "no") +
                  "  kernel_read=" + (readOk ? "yes" : "no") + "\n";
        report += readOk
            ? "         => kernel context is NOT blocked: B3 is the viable rung and\n"
              "            the user-mode refusal is a user-mode-layer effect.\n"
            : "         => kernel context is blocked too: the anti-cheat owns the\n"
              "            address space itself, and an external reader is not a way out.\n";
    } else {
        report += "IOCTL_APEXDRV_PROBE failed" + LastErrorText(GetLastError()) +
                  " - driver older than the launcher?\n";
    }

    CloseHandle(device);
    StopAndDeleteKernelService(scm);   // keep the footprint minimal
    CloseServiceHandle(scm);
    return answered;
}

