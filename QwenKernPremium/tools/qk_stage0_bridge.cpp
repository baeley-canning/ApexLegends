// qk_stage0_bridge.cpp -- external, read-only DTB lookup for PLAN stage 0.
// No ReadProcessMemory, no driver handle, no writes.  DirectoryTableBase is
// read from a live-pid-verified EPROCESS by the Python gdrv3 half, never guessed
// from a process information class that does not contain it.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

int wmain(int argc, wchar_t **argv) {
    if (argc < 3 || wcscmp(argv[1], L"--pid") != 0) {
        fprintf(stderr, "usage: qk_stage0_bridge.exe --pid N\n");
        return 2;
    }
    DWORD pid = wcstoul(argv[2], nullptr, 10);
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) {
        printf("RESULT: open_failed pid=%lu err=%lu\n", pid, GetLastError());
        return 4;
    }
    PROCESS_BASIC_INFORMATION basic{};
    ULONG len = 0;
    NTSTATUS st = NtQueryInformationProcess(h, ProcessBasicInformation,
                                   &basic, sizeof(basic), &len);
    printf("control basic_status=0x%08lX peb=%p len=%lu\n",
           (unsigned long)st, basic.PebBaseAddress, len);
    if (st >= 0 && basic.PebBaseAddress) {
        printf("RESULT: pid=%lu peb=0x%llX\n", pid,
               (unsigned long long)(ULONG_PTR)basic.PebBaseAddress);
        CloseHandle(h);
        return 0;
    }
    printf("RESULT: dtb_unavailable pid=%lu\n", pid);
    CloseHandle(h);
    return 3;
}