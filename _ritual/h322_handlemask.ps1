# h322 - which access rights can a medium-IL shell still get on the LIVE, EAAC-protected game?
# Determines whether late-attach (B2) is possible at all, and which mask NtSuspendProcess needs.
param([int] $Pid0 = 0)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HP {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    public static string Try(int pid, uint mask) {
        IntPtr h = OpenProcess(mask, false, pid);
        int e = Marshal.GetLastWin32Error();
        string r;
        if (h == IntPtr.Zero) r = string.Format("0x{0:X4} DENIED err={1}", mask, e);
        else { CloseHandle(h); r = string.Format("0x{0:X4} GRANTED", mask); }
        return r;
    }
}
'@
$outF = 'C:\h320x\h322.out'
Remove-Item $outF -Force -ErrorAction SilentlyContinue
function W($m) { $m | Out-File -FilePath $outF -Append -Encoding utf8 }
$t = if ($Pid0 -gt 0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
W ("h322 - handle rights on live game - " + (Get-Date -Format 'HH:mm:ss'))
if (-not $t) { W 'RESULT: SKIP no live r5apex_dx12'; W 'h322 DONE SKIP'; return }
W "pid      : $($t.Id)"
$masks = @(
    @{ n = 'ALL_ACCESS           '; v = 0x1F0FFF },
    @{ n = 'QUERY_LIMITED_INFO   '; v = 0x1000 },
    @{ n = 'QUERY_INFORMATION    '; v = 0x0400 },
    @{ n = 'SUSPEND_RESUME       '; v = 0x0800 },
    @{ n = 'VM_READ              '; v = 0x0010 },
    @{ n = 'VM_WRITE             '; v = 0x0020 },
    @{ n = 'VM_OPERATION         '; v = 0x0008 },
    @{ n = 'VM_R|W|OP (0x38)     '; v = 0x0038 },
    @{ n = 'CREATE_THREAD        '; v = 0x0002 },
    @{ n = 'SYNCHRONIZE          '; v = 0x00100000 },
    @{ n = 'QUERY_LTD|SYNC       '; v = 0x00101000 },
    @{ n = 'SUSPEND|QUERY_LTD    '; v = 0x00001800 },
    @{ n = 'VM_W|OP|QUERY         '; v = 0x0438 },
    @{ n = 'CREATE_PROCESS       '; v = 0x0080 }
)
foreach ($m in $masks) { W ('  ' + $m.n + ' : ' + [HP]::Try($t.Id, [uint32]$m.v)) }
W 'RESULT: see masks above (GRANTED = usable from medium IL)'
W 'h322 DONE'
W '--- read back by caller ---'
Get-Content $outF
