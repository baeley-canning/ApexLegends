// Native SystemFullProcessInformation query.  Query only; no ReadProcessMemory,
// no driver load, no game access.  Dump exact tail sizes for native extension.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

int wmain(int argc, wchar_t **argv) {
    ULONG pid = argc == 3 ? wcstoul(argv[2], NULL, 10) : 0;
    ULONG n = 1 << 20, need = 0;
    BYTE *buf = (BYTE *)VirtualAlloc(NULL, n, MEM_COMMIT, PAGE_READWRITE);
    if (!buf) return 2;
    for (int tr = 0; tr < 6; ++tr) {
        NTSTATUS st = NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)148, buf, n, &need);
        if (st == (NTSTATUS)0xC0000004) {
            n = need > n ? need + 65536 : n * 2;
            VirtualFree(buf, 0, MEM_RELEASE);
            buf = (BYTE *)VirtualAlloc(NULL, n, MEM_COMMIT, PAGE_READWRITE);
            if (!buf) return 2;
            continue;
        }
        printf("QUERY st=0x%08X need=%lu bytes=%lu\n", (ULONG)st, need, n);
        if (st != 0) break;
        for (BYTE *p = buf; ; ) {
            ULONG next = *(ULONG *)p;
            SYSTEM_PROCESS_INFORMATION *s = (SYSTEM_PROCESS_INFORMATION *)p;
            if ((ULONG)(ULONG_PTR)s->UniqueProcessId == pid) {
                printf("CONTIGUOUS_SIZE=%lu\n", next);
                printf("PID=%lu next=%lu spi=%llu next_ptr=%p\n", pid, next,
                       (unsigned long long)sizeof(*s), p + next);
                for (ULONG i = sizeof(*s); i < next; i += 8)
                    printf("rel+%04x = %016llX\n", i,
                           (unsigned long long)*(ULONG_PTR *)(p + i));
                printf("THREADS_SIZE=%u\n", s->NumberOfThreads *
                      (ULONG)sizeof(SYSTEM_THREAD_INFORMATION));
            }
            if (!next) break;
            p += next;
        }
        break;
    }
    VirtualFree(buf, 0, MEM_RELEASE);
    return 0;
}