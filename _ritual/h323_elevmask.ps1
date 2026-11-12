# h323 - same handle-rights probe as h322, but from an ELEVATED token (self-relaunches).
# Purpose: the only game process that survives is the one EA's GameService spawns
# (live, EAAC-protected). Can an admin shell still get VM_WRITE on it?
param([int] $Pid0 = 0, [switch] $Elevate)
$outF = 'C:\h320x\h323.out'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    $extra = ' -Elevate'
    if ($Pid0 -gt 0) { $extra += " -Pid0 $Pid0" }
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra)
    exit 0
}
Remove-Item $outF -Force -ErrorAction SilentlyContinue
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HP3 {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint c);
    public static string Try(int pid, uint mask) {
        IntPtr h = OpenProcess(mask, false, pid);
        int e = Marshal.GetLastWin32Error();
        if (h == IntPtr.Zero) return string.Format("0x{0:X4} DENIED err={1}", mask, e);
        CloseHandle(h); return string.Format("0x{0:X4} GRANTED", mask);
    }
}
'@
function W($m) { $m | Out-File -FilePath $outF -Append -Encoding utf8 }
$t = if ($Pid0 -gt 0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
W ("h323 - handle rights on live game, elevated=$isAdmin - " + (Get-Date -Format 'HH:mm:ss'))
if (-not $t) { W 'RESULT: SKIP no live r5apex_dx12'; W 'h323 DONE SKIP'; return }
$procId = $t.Id
$ci = Get-CimInstance Win32_Process -Filter "ProcessId=$procId"
W "pid      : $procId  ppid=$($ci.ParentProcessId)  exe=$($ci.ExecutablePath)"
W "started  : $($t.StartTime)"
try { W "modules  : " + (((Get-Process -Id $procId).Modules | ForEach-Object { $_.ModuleName }) -join ',') } catch { W "modules  : err $($_.Exception.Message)" }
$masks = @(
    @{ n='ALL_ACCESS        '; v=0x1F0FFF }, @{ n='QUERY_LIMITED_INFO'; v=0x1000 },
    @{ n='SUSPEND_RESUME    '; v=0x0800 }, @{ n='VM_READ           '; v=0x0010 },
    @{ n='VM_WRITE          '; v=0x0020 }, @{ n='VM_OPERATION      '; v=0x0008 },
    @{ n='VM_R|W|OP         '; v=0x0038 }, @{ n='CREATE_THREAD     '; v=0x0002 },
    @{ n='CREATE_PROCESS    '; v=0x0080 }, @{ n='SYNCHRONIZE       '; v=0x100000 },
    @{ n='ALLMINUS_SUSPEND  '; v=0x1F07FF }
)
foreach ($m in $masks) { W ('  ' + $m.n + ' : ' + [HP3]::Try($procId, [uint32]$m.v)) }
W 'RESULT: see masks above'
W 'h323 DONE'
Get-Content $outF
