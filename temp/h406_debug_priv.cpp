// Read-only SystemExtendedHandleInformation with documented debug privilege.
// Restores previous privilege state in the same process before exit.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {PVOID Object; HANDLE Owner, Handle; ACCESS_MASK Access;
               USHORT Index, Type; ULONG Attrs, Reserved;} HE;

static BOOL Priv(const wchar_t *name, BOOL enable, TOKEN_PRIVILEGES *old) {
    HANDLE t; LUID l;
    if(!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY, &t)) return FALSE;
    if(!LookupPrivilegeValueW(NULL,name,&l)){CloseHandle(t);return FALSE;}
    DWORD len=0;
    if(!GetTokenInformation(t,TokenPrivileges,old,sizeof(*old),&len)){CloseHandle(t);return FALSE;}
    TOKEN_PRIVILEGES p=*old; p.PrivilegeCount=1; p.Privileges[0].Luid=l;
    p.Privileges[0].Attributes=enable?SE_PRIVILEGE_ENABLED:0;
    BOOL ok=AdjustTokenPrivileges(t,FALSE,&p,0,NULL,NULL);
    CloseHandle(t); return ok;
}

int wmain(int argc,wchar_t**argv){
    DWORD targetId=argc>2?wcstoul(argv[2],NULL,10):GetCurrentProcessId();
    HANDLE ph=OpenProcess(PROCESS_QUERY_INFORMATION,FALSE,targetId);
    if(!ph){printf("OpenProcess err=%lu\n",GetLastError());return 2;}
    TOKEN_PRIVILEGES restore{}; DWORD attr=0; attr=0;
    printf("priv_restore=%d\n", Priv(L"SeDebugPrivilege",TRUE,&restore));
    ULONG need=0,len=1<<20; BYTE*buf=(BYTE*)VirtualAlloc(NULL,len,MEM_COMMIT,PAGE_READWRITE);
    NTSTATUS st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)64,buf,len,&need);
    if(st==0xC0000004){
        len=need+4096; VirtualFree(buf,0,MEM_RELEASE);
        buf=(BYTE*)VirtualAlloc(NULL,len,MEM_COMMIT,PAGE_READWRITE);
        st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)64,buf,len,&need);
    }
    printf("self pid=%lu handle=%p st=%08X count=%llu\n",GetCurrentProcessId(),ph,st,
           *(unsigned long long*)buf);
    if(st==0){HE*e=(HE*)(buf+16);
        for(ULONG_PTR i=0;i<*(ULONG_PTR*)buf;++i)
            if(e[i].Owner==(HANDLE)(ULONG_PTR)GetCurrentProcessId() && e[i].Handle==ph)
                printf("EPROCESS=%p owner=%lu handle=%p type=%u access=%08X\n",
                    e[i].Object,(ULONG)(ULONG_PTR)e[i].Owner,e[i].Handle,e[i].Type,e[i].Access);
    }
    Priv(L"SeDebugPrivilege",FALSE,&restore);
    VirtualFree(buf,0,MEM_RELEASE);
    CloseHandle(ph);
    return 0;
}