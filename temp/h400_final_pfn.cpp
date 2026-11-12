// Exact `SystemSuperfetchInformation` positive control. Everything caller
// controlled is from existing Windows. Existing gdrv3 handles page bytes.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <string.h>
typedef struct {
    ULONG Version, Magic, Class;
    PVOID Info;
    ULONG Length;
} SSIZEINFO;

NTSTATUS NTAPI QuerySys(SYSTEM_INFORMATION_CLASS klass, PVOID q, ULONG n, PULONG need) {
    return NtQuerySystemInformation(klass,q,n,need);
}

int wmain(){
    char marker[] = "LOCAL-SUPERFETCH-MARK";
    BYTE buf[0xd8]{};
    ULONG count_need=0;
 *((ULONG64*)buf)=0x0000000100000001;
 *((ULONG*)buf)=1;
    *((ULONG64*)(buf+8))=1;
    *((ULONG64*)(buf+0xc0))=(ULONG_PTR)marker;
 SSIZEINFO s{45,0x4375686B,12,buf,sizeof(buf)};
NTSTATUS st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)79,&s,sizeof(s),&count_need);
    printf("size=%zu tweak=%llu payload=%zu status=%08X need=%lu\n",
        sizeof(s),(unsigned long long)((ULONG64*)buf)[0],(ULONG64)s.Length,
        (ULONG)st,count_need);
    for(int i=0;i<32;i++)printf("%02X",buf[i]);
    printf(" entry: ");
    for(int i=0xc0;i<0xd8;i++)printf("%02X",buf[i]);
    printf("\n");
    return st;
}