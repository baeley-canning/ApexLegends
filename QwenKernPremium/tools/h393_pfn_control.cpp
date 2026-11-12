// Read-only PFN control. Exact structure sizes/versions on this host are
// required; the raw output is dumped rather than dereferenced speculatively.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>

struct SfQuery { ULONG Version, Magic, Class; void *Info; ULONG Length; };
struct PfQuery { ULONG Version, Magic, Class; void *Info; };

int wmain() {
    BYTE *buf = (BYTE *)VirtualAlloc(NULL, 0x2000, MEM_COMMIT, PAGE_READWRITE);
    if (!buf) return 2;
    VirtualLock(buf, 0x2000);
    const char marker[] = "PFN-CONTROL-524377";
    memcpy(buf, marker, sizeof(marker));
    ULONG raw_len = 0xD8;  // exactly one MMPFN_IDENTITY at offset 0xC0
    for (int attempt = 0; attempt < 1; ++attempt) {
        BYTE raw[0x440]{};
        ((ULONG *)raw)[0] = 1;         // PF_PFN_PRIO_REQUEST_VERSION
        ((ULONG *)raw)[1] = 0;         // query, not priority mutation
        ((ULONG64 *)raw)[1] = 1;       // PfnCount
        ((ULONG64 *)raw)[24] = (ULONG64)(ULONG_PTR)buf;
        PfQuery q{0, 0, 6, raw};
        ULONG version = 1;
        SfQuery s{(ULONG)version, 0x4375686B, 12, &q, raw_len};
        ULONG need = 0;
        NTSTATUS st = NtQuerySystemInformation(79, &s, sizeof(s), &need);
        printf("version=%d status=0x%08lX need=%lu out=", version, (ULONG)st, need);
        for (int j = 0; j < 64; ++j) printf("%02x", raw[j]);
        printf(" marker=%s\n", marker);
    }
    VirtualFree(buf, 0, MEM_RELEASE);
    return 0;
}