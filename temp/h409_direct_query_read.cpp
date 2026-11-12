// Tiny narrow normal documented API A/B: query FULL not limited + VM_READ.
// SeDebugPrivilege only in this process, restores old token adjustment.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>

static void debug(BOOL on){
 HANDLE tok; LUID l;
 if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES,&tok))return;
 if(LookupPrivilegeValueW(NULL,L"SeDebugPrivilege",&l)){
   TOKEN_PRIVILEGES tp{1,l,on?2u:0u};
   AdjustTokenPrivileges(tok,FALSE,&tp,0,NULL,NULL);
 }
 CloseHandle(tok);
}
int wmain(int argc,wchar_t**argv){
    DWORD pid=argc>2?wcstoul(argv[2],NULL,10):GetCurrentProcessId();
    debug(TRUE);
    HANDLE h=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ,FALSE,pid);
    printf("queryfull_handle=%p err=%lu\n",h,GetLastError());fflush(stdout);
    if(!h)return 2;
    PROCESS_BASIC_INFORMATION b{};
    NtQueryInformationProcess(h,ProcessBasicInformation,&b,sizeof(b),NULL);
    printf("PEB=%p\n",b.PebBaseAddress);fflush(stdout);
    ULONG64 image=0;
    SIZE_T got=0;
    BOOL ok=ReadProcessMemory(h,(BYTE*)b.PebBaseAddress+0x10,&image,8,&got);
    printf("peb.Read err=%lu ok=%d got=%llu base=%llX\n",GetLastError(),ok,
          (unsigned long long)got,(unsigned long long)image);
    if(ok){
        char mz[4];got=0;
        ok=ReadProcessMemory(h,(void*)image,mz,4,&got);
        printf("MZ err=%lu ok=%d mz=%02X %02X %02X %02X\n",GetLastError(),ok,
            (BYTE)mz[0],(BYTE)mz[1],(BYTE)mz[2],(BYTE)mz[3]);
    }
    CloseHandle(h);debug(FALSE);return ok?0:1;
}