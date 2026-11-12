// Existing OS process query only -- emit process row to prove pointer layout.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdlib.h>
int wmain(int argc,wchar_t**argv){
 ULONG pid=argc==3?wcstoul(argv[2],NULL,10):0,n=1<<20,need=0;
 BYTE*p=(BYTE*)VirtualAlloc(NULL,n,MEM_COMMIT,PAGE_READWRITE);
 NTSTATUS st=NtQuerySystemInformation((SYSTEM_INFORMATION_CLASS)148,p,n,&need);
 printf("st=%08X need=%u base=%p spiFixed=%llu spiWithOne=%llu threads=%llu\n",(ULONG)st,
        need,p,(unsigned long long)(sizeof(SYSTEM_PROCESS_INFORMATION)-
                                    sizeof(SYSTEM_THREAD_INFORMATION)),
        (unsigned long long)sizeof(SYSTEM_PROCESS_INFORMATION),
        (unsigned long long)sizeof(SYSTEM_THREAD_INFORMATION));
 for(BYTE*q=p;;){SYSTEM_PROCESS_INFORMATION*s=(SYSTEM_PROCESS_INFORMATION*)q;
     wchar_t *nul=(s->ImageName.Buffer && s->ImageName.Length<1024)?
                    wcsstr(s->ImageName.Buffer,L"r5apex"):NULL;
     printf("ptr=%p PID=%llu next=%lu threads=%lu nameLen=%u imageOffNext=%zu\n",
         q,(unsigned long long)s->UniqueProcessId,*(ULONG*)q,
         s->NumberOfThreads,s->ImageName.Length,
         (size_t)((BYTE*)s->ImageName.Buffer-q));
     if(s->UniqueProcessId==(HANDLE)(ULONG_PTR)pid){
       ULONG len=sizeof(SYSTEM_PROCESS_INFORMATION)+
         ((ULONG)s->NumberOfThreads-1)*sizeof(SYSTEM_THREAD_INFORMATION);
       ULONG extActual_end=*(ULONG*)q;
       printf("MATCH full row bytes=%u\n",len);
       FILE*f=fopen("C:\\Users\\New User\\OneDrive\\Desktop\\cheating\\temp\\h398_row.bin","wb");
       if(f){fwrite(q,1,len,f);fclose(f);}
     }
     ULONG nx=*(ULONG*)q;if(!nx)break;
     if(nx<256||nx>n)break;
     q+=nx;
     if(q>=p+n)break;
 }
 VirtualFree(p,0,MEM_RELEASE);return 0;
}