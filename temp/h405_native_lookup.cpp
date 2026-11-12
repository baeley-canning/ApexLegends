// Use documented SystemExtendedHandleInformation to identify _EPROCESS exactly.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { PVOID Object; HANDLE Owner; HANDLE Handle; ACCESS_MASK Access;
    USHORT BackTrace; USHORT Type; ULONG Attributes; DWORD Reserved; } HENTRY;

int wmain(int argc, wchar_t **argv) {
    if (argc != 3) return 2;
    DWORD gamepid = wcstoul(argv[2], NULL, 10), self = GetCurrentProcessId();
    HANDLE target = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, gamepid);
    if (!target) return 3;
    DWORD mypid = self;
    ULONG length=1<<20, need=0;
    BYTE *buf=(BYTE*)VirtualAlloc(NULL,length,MEM_COMMIT,PAGE_READWRITE);
    for (int attempt=0; attempt<4; ++attempt) {
        NTSTATUS st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)64,buf,length,&need);
        if(st == (NTSTATUS)0xC0000004) {
            length = need + 65536;
            VirtualFree(buf,0,MEM_RELEASE);
            buf=(BYTE*)VirtualAlloc(NULL,length,MEM_COMMIT,PAGE_READWRITE);
            continue;
        }
        printf("status=%08X entries=%llu process=%lu own=%lu handle=%p\n",
            st,*(unsigned long long*)buf,gamepid,self,target);
        if(st == 0) {
            HENTRY *e=(HENTRY*)(buf+16);
            for (ULONG_PTR i=0; i<*(ULONG_PTR*)buf; ++i) {
                if ((ULONG_PTR)e[i].Owner == self) {
                    printf("own object=%p handle=%p type=%u access=%08X ",
                        e[i].Object,e[i].Handle,e[i].Type,e[i].Access);
                    if (e[i].Handle == target)
                        printf("APX_MATCH\n");
                    else printf("\n");
                }
            }
        }
        break;
    }
    if(buf) VirtualFree(buf,0,MEM_RELEASE);
    CloseHandle(target);
    return 0;
}