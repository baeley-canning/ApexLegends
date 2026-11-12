# h321 - is 0x186AA triggered by CREATE_SUSPENDED, or by an external suspend/resume of a
#        game process that survived creation? Takes an ALREADY-LIVE pid created by cmd/Start-Process
#        (h158/28644 lineage), suspends it externally for HoldMs, resumes, watches.
# One variable: external NtSuspend/NtResume on a surviving instance. No create, no inject.
param(
    [int] $Pid0    = 0,      # 0 = auto-detect r5apex_dx12
    [int] $HoldMs  = 600,
    [int] $WatchMs = 6000
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NT {
    [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr h);
    [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr h);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
}
'@
$outF = 'C:\h320x\h321.out'
function W($m) { $m | Tee-Object -FilePath $outF -Append | Out-Host }
Remove-Item $outF -Force -ErrorAction SilentlyContinue

$target = if ($Pid0 -gt 0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Sort-Object StartTime | Select-Object -First 1 }
W ("h321 - external suspend/resume of a LIVE game instance - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if (-not $target) { W 'RESULT: SKIP no live r5apex_dx12 to test (create one via cmd first)'; W 'h321 DONE SKIP'; return }
$procId = $target.Id
$startT = $target.StartTime
W "pid      : $procId (started $startT, age $([int]((Get-Date) - $startT).TotalSeconds) s)"
W "hold     : ${HoldMs} ms suspended, then resume"
W "watch    : ${WatchMs} ms"

$h = [NT]::OpenProcess(0x1F0FFF, $false, $procId)
if ($h -eq [IntPtr]::Zero) { W ('RESULT: FAIL OpenProcess err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); W 'h321 DONE FAIL'; return }
W ('handle   : ' + $h)

$rc = [NT]::NtSuspendProcess($h)
W "suspend  : rc=$rc (0 = ok)"
Start-Sleep -Milliseconds $HoldMs
$rc2 = [NT]::NtResumeProcess($h)
W "resume   : rc=$rc2 (0 = ok)"

# read-back: is it alive, and if not, what exit code
$sw = [Diagnostics.Stopwatch]::StartNew()
$alive = $true
while ($sw.ElapsedMilliseconds -lt $WatchMs) {
    Start-Sleep -Milliseconds 250
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $p) { $alive = $false; break }
}
$ms = [int]$sw.ElapsedMilliseconds
if ($alive) {
    W "after    : alive=True still running after ${ms} ms post-resume"
    W 'RESULT: PASS survived external suspend/resume -> trigger is CREATE_SUSPENDED, not our handle'
    W 'h321 DONE PASS'
} else {
    $code = 0
    [void][NT]::GetExitCodeProcess($h, [ref]$code)
    W ("after    : alive=False died ${ms} ms after resume, exitCode=0x{0:X8}" -f $code)
    W ("RESULT: FAIL died exit=0x{0:X8} -> any external suspend/resume kills it" -f $code)
    W 'h321 DONE FAIL'
}
[void][NT]::CloseHandle($h)
