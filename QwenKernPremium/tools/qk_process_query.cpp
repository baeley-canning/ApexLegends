// Query-only EPROCESS address lookup for the read-only physical transport.
// No process memory reads/writes; the Python half validates object layout.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma pack(push, 8)
struct SysProcessFull {
    SYSTEM_PROCESS_INFORMATION base;
    ULONG_PTR ProcessorTime;
    ULONG_PTR Reserved3[7];        // SYSTEM_PROCESS_INFORMATION_EXTENSION below
    HANDLE UniqueProcessKey;
    HANDLE ProcessObject;           // exact offset is read back, not guessed here
    ULONG DiskCounters[8];
};
#pragma pack(pop)

int wmain(int argc, wchar_t **argv) {
    if (argc != 3 || wcscmp(argv[1], L"--pid")) return 2;
    ULONG_PTR target = wcstoul(argv[2], NULL, 10);
    ULONG size = 1 << 20, need = 0;
    BYTE *buf = (BYTE *)VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE,
                                    PAGE_READWRITE);
    if (!buf) return 3;
    for (int tries = 0; tries < 6; ++tries) {
        NTSTATUS st = NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)148,
                                              buf, size, &need);
        if (st == 0) break;
        printf("query_status=0x%08lX need=%lu size=%lu\n", (ULONG)st, need, size);
        if (st != (NTSTATUS)0xC0000004) { VirtualFree(buf, 0, MEM_RELEASE); return 4; }
        size = need > size ? need + 0x10000 : size * 2;
        VirtualFree(buf, 0, MEM_RELEASE);
        buf = (BYTE *)VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (!buf) return 3;
        if (tries == 5) return 4;
    }
    int found = 0;
    BYTE *p = buf;
    while (p) {
        SYSTEM_PROCESS_INFORMATION *s = (SYSTEM_PROCESS_INFORMATION *)p;
        ULONG next = *(ULONG *)p;
        if (s->UniqueProcessId == (HANDLE)target) {
            printf("row_next=%lu spi_size=%llu threads=%lu handlecount=%lu\n",
                   next, (unsigned long long)sizeof(*s), s->NumberOfThreads,
                   s->HandleCount);
            printf("RESULT: pid=%llu at=%p bytes_to_end=%lu\n",
                   (unsigned long long)target, (void *)p,
                   (ULONG)((buf + size) - p));
            // Print the tail as qwords; layouts differ by OS build.
                for (int i = 0; i < 128; ++i) {
                ULONG_PTR x = ((ULONG_PTR *)(p + sizeof(*s)))[i];
                printf("tail+%03x = 0x%llX\n", i * 8, (unsigned long long)x);
            }
            for (int i = 0; i < 128 && i*16 < size; ++i) {
                printf("rowbytes+%04x = ", i * 16);
                for (int j = 0; j < 16; ++j) printf("%02X", p[i*16+j]);
                printf("\n");
            }
            found = 1;
            break;
        }
        if (!next) break;
        p += next;
    }
    if (!found) printf("RESULT: pid_not_found\n");
    VirtualFree(buf, 0, MEM_RELEASE);
    return found ? 0 : 5;
}