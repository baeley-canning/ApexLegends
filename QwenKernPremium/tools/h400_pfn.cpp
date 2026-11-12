// Existing Windows Superfetch PFN query positive control; no game access.
// Exact layout from ntpfapi.h: x64 envelope 24 bytes, one 0xd8 request.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <string.h>

struct SuperfetchInfo {
    ULONG Version;
    ULONG Magic;
    ULONG InfoClass;
    PVOID Payload;
    ULONG Size;
};
struct PfQuery {
    ULONG Version;
    ULONG Magic;
    ULONG InfoClass;
    ULONG Padding;
    PVOID Data;
    ULONG Size;
};

int wmain(){
    char marker[0x1000]{};
    memcpy(marker,"H400-PFN-CONTROL",17);
    BYTE buffer[0xd8]{};
    *(ULONG*)buffer=1;
    *(ULONG64*)(buffer+8)=1;
    *(ULONG64*)(buffer+0xc0)=(ULONG64)(ULONG_PTR)marker;
            PfQuery q{0,0,6,0,buffer,0xd8};
    const ULONG envelope=(ULONG)(6 | (1<<31));
    ULONG need=0;
    for(ULONG ver=1; ver<90; ++ver){
    ULONG sizes[]={sizeof(SuperfetchInfo),sizeof(PfQuery)};
    printf("actual sizes sf=%zu q=%zu\n", sizeof(SuperfetchInfo), sizeof(PfQuery));
        for(int j=0;j<2;++j){
            SuperfetchInfo s{ver,0x4375686b,12,buffer,0xd8};
            memset(buffer+8,0,0xd0);
            // PfnCount is REQUIRED non-zero. Resetting it here was invalid per docs.
            *(ULONG64*)(buffer+8)=1;
            *(ULONG64*)(buffer+0xc0)=(ULONG64)(ULONG_PTR)marker;
            NTSTATUS st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)79,
                                                &s,sizes[j],&need);
            printf("version=%lu classlen=%lu status=%08X need=%lu ",ver,
                    sizes[j],(ULONG)st,need);
            for(int i=0;i<16;i++)printf("%02X",buffer[i]);printf(" : ");
            for(int i=0xc0;i<0xd8;i++)printf("%02X",buffer[i]);printf("\n");
            if(st==0){ printf("FOUND v=%lu len=%lu\n",ver,sizes[j]);return 0; }
            if(st!=0xC0000004)return 2;
        }
    }
    return 1;
}