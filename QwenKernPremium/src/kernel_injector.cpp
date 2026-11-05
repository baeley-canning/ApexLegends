#include "injector.h"
#include "apex_driver_ioctl.h"

#include <iostream>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>
#include <algorithm>

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

// NTSTATUS STATUS_PENDING: the loader APC was queued but not yet delivered.
constexpr LONG kStatusPending = 0x00000103L;

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

    // The driver no longer trusts this address: since ABI v4 it resolves
    // kernel32!LoadLibraryW inside the target itself (PEB -> Ldr -> kernelbase
    // export table) and reports ResolvePath/BasesDiffer.  The local value is
    // still sent as a cross-check datum, and is what a v3 driver would use.
    const ULONG64 loadLibraryAddress = reinterpret_cast<ULONG64>(
        GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryW"));

    // The driver delivers the loader as a user-mode APC, so it needs a thread of
    // the target to queue onto (v3 - ZwCreateThreadEx is not exported on 26100).
    // EnumerateThreads() yields Toolhelp order, i.e. creation order, so index 0
    // is the MAIN thread - the one that spends its life in the loader lock.  The
    // list is rotated by one to try a worker first and keep the main thread as
    // the last resort instead of the first choice.
    std::vector<DWORD> targetThreads = EnumerateThreads(targetPid);
    if (targetThreads.empty()) {
        result.errorMessage = "no thread found in PID " + std::to_string(targetPid) +
                              " - nothing to queue the loader APC on";
        CloseServiceHandle(scm);
        return result;
    }
    if (targetThreads.size() > 1) {
        std::rotate(targetThreads.begin(), targetThreads.begin() + 1,
                    targetThreads.end());
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

    // Refuse a driver older than this launcher: v3 moved the inject rung to an
    // APC and put ThreadId in the request, so a v2 driver would misread it.
    {
        APEXDRV_VERSION_INFO versionInfo{};
        DWORD versionBytes = 0;
        if (!DeviceIoControl(hDevice, IOCTL_APEXDRV_VERSION, &versionInfo, sizeof(versionInfo),
                             &versionInfo, sizeof(versionInfo), &versionBytes, nullptr)) {
            result.errorMessage = "IOCTL_APEXDRV_VERSION failed" + LastErrorText(GetLastError());
            CloseHandle(hDevice);
            StopAndDeleteKernelService(scm);
            CloseServiceHandle(scm);
            return result;
        }
        if (versionInfo.Version < APEXDRV_VERSION) {
            char versionBuffer[160];
            sprintf_s(versionBuffer, sizeof(versionBuffer),
                      "driver ABI v%lu < v%d - rebuild and reload apexdrv.sys",
                      static_cast<unsigned long>(versionInfo.Version),
                      static_cast<int>(APEXDRV_VERSION));
            result.errorMessage = versionBuffer;
            CloseHandle(hDevice);
            StopAndDeleteKernelService(scm);
            CloseServiceHandle(scm);
            return result;
        }
        std::cout << "[*] driver ABI v" << versionInfo.Version << std::endl;
    }

    // Control read before the mutation (R3): the target's current loader state and
    // its OWN kernelbase base.  No allocation, no thread, no APC - the inject below
    // is the only mutation this function performs.
    {
        APEXDRV_TARGETINFO_REQUEST info{};
        info.ProcessId  = targetPid;
        info.ThreadId   = targetThreads.front();
        DWORD infoBytes = 0;
        if (DeviceIoControl(hDevice, IOCTL_APEXDRV_TARGETINFO, &info, sizeof(info),
                            &info, sizeof(info), &infoBytes, nullptr)) {
            std::cout << "[*] targetinfo: modules=" << info.ModuleCount
                      << " kernelbase=0x" << Hex64(info.KernelBaseBase)
                      << " self=0x" << Hex64(info.SelfKernelBaseBase)
                      << " differ=" << info.BasesDiffer
                      << " target LoadLibraryW=0x" << Hex64(info.ResolvedLoadLibrary)
                      << " (rva 0x" << std::hex << info.LoadLibraryRva << std::dec
                      << ", ours 0x" << Hex64(loadLibraryAddress) << ")"
                      << " lastError=" << info.LastErrorValue << std::endl;
            if (info.BasesDiffer != 0) {
                std::cout << "[!] kernelbase is NOT at the same base in target and "
                             "launcher - the locally resolved LoadLibraryW points "
                             "at nothing in the target" << std::endl;
            }
            if (info.KernelBaseBase == 0) {
                std::cout << "[!] target has no kernelbase.dll in its module list"
                          << std::endl;
            }
        } else {
            std::cout << "[~] IOCTL_APEXDRV_TARGETINFO failed"
                      << LastErrorText(GetLastError()) << std::endl;
        }
    }

    APEXDRV_INJECT_REQUEST request{};
    request.ProcessId          = targetPid;
    request.Flags              = APEXDRV_FLAG_RESOLVE_IN_TARGET;
    request.ThreadId           = targetThreads.front();
    request.LoadLibraryAddress = loadLibraryAddress;
    {
        const std::wstring wideDll = WidenAscii(dllPath);
        wcsncpy_s(request.DllPath, APEXDRV_MAX_PATH_CHARS, wideDll.c_str(), _TRUNCATE);
    }

    // A user-mode APC only runs when its thread next returns to user mode alertably.
    // EnumerateThreads() order is arbitrary and session-0/Win32 worker threads often
    // sit in non-alertable kernel waits forever, so ONE thread is not enough: try them
    // in order until one delivers (status 0) and only fall back to PENDING when the
    // whole short list was queued without a confirmed delivery.
    DWORD bytesReturned = 0;
    BOOL  ioctlOk       = FALSE;
    const size_t kMaxThreadTries = targetThreads.size() < 6 ? targetThreads.size() : 6;

    for (size_t attempt = 0; attempt < kMaxThreadTries; ++attempt) {
        request.ThreadId     = targetThreads[attempt];
        request.ResultStatus = 0;
        bytesReturned        = 0;
        ioctlOk = DeviceIoControl(hDevice, IOCTL_APEXDRV_INJECT,
                                  &request, sizeof(request),
                                  &request, sizeof(request),
                                  &bytesReturned, nullptr);
        if (!ioctlOk) break;
        if (request.ResultStatus == 0) break;                        // delivered
        if (request.ResultStatus == kStatusPending) continue;        // next thread
        break;   // hard NTSTATUS - stop, no point burning the other threads
    }

    if (!ioctlOk) {
        result.errorMessage = "DeviceIoControl(IOCTL_APEXDRV_INJECT) failed" +
                              LastErrorText(GetLastError());
    } else {
        // Everything below is the v4 verdict block: the driver reports what the
        // call DID, not that it was queued.  Module count is the primary signal -
        // LastError only explains a failure, and 0 with no new module means the
        // resolver address was wrong (the call ran into nothing).
        const bool loaded = (request.ModuleCountAfter > request.ModuleCountBefore);

        std::cout << "[*] delivery: tid=" << request.ThreadId
                  << " resolve_path=" << request.ResolvePath
                  << " bases_differ=" << request.BasesDiffer
                  << " LoadLibraryW=0x" << Hex64(request.ResolvedLoadLibrary)
                  << " lastError=" << request.LoadLibraryLastError
                  << " (read status 0x" << std::hex
                  << static_cast<unsigned long>(request.StatusReadResult) << std::dec
                  << ")" << std::endl;
        std::cout << "[*] modules: before=" << request.ModuleCountBefore
                  << " after=" << request.ModuleCountAfter;

        if (loaded) {
            std::wcout << L" new module: " << request.NewModuleName
                       << L" @ 0x" << std::hex << request.NewModuleBase << std::dec
                       << std::endl;
        } else {
            std::cout << " (no module appeared)" << std::endl;
        }

        if (loaded) {
            result.success       = true;
            result.threadId      = request.ThreadId;
            result.dllBaseAddress = reinterpret_cast<HMODULE>(
                static_cast<ULONG_PTR>(request.NewModuleBase));

            std::cout << "[+] Kernel injection SUCCESS - " << request.ModuleCountAfter
                      << " modules in target, apexcheat.dll at 0x"
                      << std::hex << request.NewModuleBase << std::dec << std::endl;
        } else if (request.ResultStatus == kStatusPending) {
            // Queued, no thread returned inside the driver's window.  The APCs are
            // still armed, so this is not a failure - but it is not proof either.
            result.threadId = request.ThreadId;
            result.errorMessage = "loader APC queued on " +
                std::to_string(kMaxThreadTries) +
                " thread(s), none delivered inside the driver window (STATUS_PENDING)";
            std::cout << "[~] " << result.errorMessage << std::endl;
        } else if (request.ResultStatus != 0) {
            char statusBuffer[32] = { 0 };
            sprintf_s(statusBuffer, sizeof(statusBuffer), "0x%08lX",
                      static_cast<unsigned long>(request.ResultStatus));
            result.errorMessage = std::string("Driver reported NTSTATUS ") + statusBuffer;
            std::cout << "[-] " << result.errorMessage << std::endl;
        } else {
            // The APC fired, LoadLibraryW ran and no module appeared: read the
            // reason off LastError instead of inventing one.
            const LONG loaderError = request.LoadLibraryLastError;
            const char* reason = "unknown - LastError 0 with no module means the "
                                 "resolved address did not enter LoadLibraryW";
            if (loaderError == 126) {
                reason = "ERROR_MOD_NOT_FOUND - the target cannot see the DLL path "
                         "(CWD / redirection / 32-bit view)";
            } else if (loaderError == 193) {
                reason = "ERROR_BAD_EXE_FORMAT - the target rejected the image";
            } else if (loaderError == 998) {
                reason = "ERROR_NOACCESS - the loader faulted on the path buffer or "
                         "the image (manual map is next)";
            } else if (loaderError == 1114) {
                reason = "ERROR_DLL_INIT_FAILED - DllMain returned FALSE";
            } else if (loaderError == 87) {
                reason = "ERROR_INVALID_PARAMETER - target-side address is not a "
                         "code address";
            }
            result.threadId = request.ThreadId;
            result.errorMessage = std::string("delivered, but LoadLibraryW left no "
                                              "module (LastError ") +
                                  std::to_string(loaderError) + "): " + reason;
            std::cout << "[-] " << result.errorMessage << std::endl;
        }
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

