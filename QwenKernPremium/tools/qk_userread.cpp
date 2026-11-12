#include "qk_userread.hpp"
#include <stdio.h>

static void QkPrivilege(bool enable) {
    HANDLE tok;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES, &tok)) return;
    LUID id;
    if (LookupPrivilegeValueW(nullptr, L"SeDebugPrivilege", &id)) {
        TOKEN_PRIVILEGES tp{1, id, enable ? SE_PRIVILEGE_ENABLED : 0};
        AdjustTokenPrivileges(tok, FALSE, &tp, 0, nullptr, nullptr);
    }
    CloseHandle(tok);
}

QkUserRead::QkUserRead(DWORD pid) : handle_(nullptr), peb_(nullptr) {
    PROCESS_BASIC_INFORMATION basic{};
    basic.PebBaseAddress = nullptr;
    QkPrivilege(true);
    handle_ = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    printf("OPEN pid=%lu h=%p err=%lu\n", (unsigned long)pid, handle_, GetLastError());
    if (!handle_) return;
    PROCESS_BASIC_INFORMATION info{};
    NTSTATUS status = NtQueryInformationProcess(handle_, ProcessBasicInformation,
                                                &info, sizeof(info), nullptr);
    printf("Q_INFO status=0x%08lX PEB=%p\n", (ULONG)status, info.PebBaseAddress);
    peb_ = info.PebBaseAddress;
}

QkUserRead::~QkUserRead() { if (handle_) CloseHandle(handle_); }

bool QkUserRead::read(uintptr_t addr, void *dst, SIZE_T size) const {
    SIZE_T n = 0;
    return handle_ && dst && size && ReadProcessMemory(
        handle_, reinterpret_cast<LPCVOID>(addr), dst, size, &n) && n == size;
}

uintptr_t QkUserRead::module_base() const {
    uintptr_t base = 0;
    if (!read(reinterpret_cast<uintptr_t>(peb_) + 0x10, &base, sizeof(base))) {
        printf("PEB_READ base failed peb=%p err=%lu\n", peb_, GetLastError());
        fflush(stdout);
    }
    return base;
}