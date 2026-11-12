// ProcessFullProcessInformation query-only reference for extension validation.
// No game memory reading. Proves native process-row layout, no driver decision.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>

int wmain(){
    ULONG n=1<<20, need=0;
    BYTE*p=(BYTE*)VirtualAlloc(NULL,n,MEM_COMMIT,PAGE_READWRITE);
    DWORD pid=GetCurrentProcessId();
    NTSTATUS st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)148,p,n,&need);
 printf("Q=%08X self=%lu n=%u threads=%zu\n",st,pid,n,
            sizeof(SYSTEM_THREAD_INFORMATION));
    for(BYTE*q=p;;){
        SYSTEM_PROCESS_INFORMATION*s=(SYSTEM_PROCESS_INFORMATION*)q;
        if(s->UniqueProcessId==(HANDLE)(ULONG_PTR)pid){
            ULONG nent=s->NumberOfThreads;
            BYTE*ext=q+sizeof(*s)+(nent-1)*sizeof(SYSTEM_THREAD_INFORMATION);
            printf("q=%p next=%lu threads=%lu found_ext=%p\n",q,*(ULONG*)q,nent,ext);
            for(int i=0;i<24;i++)printf("%03x: %016IX\n",i*8,((size_t*)ext)[i]);
        }
        ULONG next=*(ULONG*)q;if(!next)break;q+=next;
    }
    VirtualFree(p,0,MEM_RELEASE); return 0;
}