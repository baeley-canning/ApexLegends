# h321_fire_kprobe.ps1 - h321: same intent as h320 (ONE transient --kernel-probe IOCTL against a
# live game), but the reload no longer deletes a service whose driver is still loaded (that put
# the name in marked-for-deletion state, StartService returned 1058, and h320 never sent an
# IOCTL).  Order is now: RUNNING -> leave alone; otherwise stop -> wait for unload -> delete ->
# create -> dse 0 -> start -> dse 22 verify.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h321_fire_kprobe.out'
$d    = 'C:\Users\Public\p37'
$sys  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) {
    Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' not elevated (pid ' + $PID + ') - requesting elevation')
    try {
        $e = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs -PassThru -Wait -EA Stop
        Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' elevated child exited ' + $e.ExitCode)
    } catch { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' elevation failed: ' + $_.Exception.Message) }
    exit 0
}
function Kdu([string[]]$a, [int]$cap = 25000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'kdu.exe'; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit($cap)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
function Dse($Q) { $o = Kdu @('-prv', '20', '-dse', $Q); if ($o -match 'value:\s*([0-9A-Fa-f]+)') { return $matches[1] } return '' }
Lg '===== h321 kernel transient probe (elevated, 15 min fuse) ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=[' + (SvcQ) + '] drv sha=' + (Get-FileHash $sys -Algorithm SHA256).Hash.Substring(0, 16))
if ((Get-FileHash $sys -Algorithm SHA256).Hash -ne '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C') { Lg 'RESULT: FAIL - staged image is not the v14 build'; Emit; exit 1 }
$q = SvcQ
if ($q -match 'RUNNING') {
    Lg 'driver already RUNNING - service left alone (no delete), no DSE change needed'
} else {
    if ($q -notmatch 'does not exist') {
        & "$env:SystemRoot\system32\sc.exe" stop apexdrv 2>&1 | Out-Null
        $w = [Diagnostics.Stopwatch]::StartNew(); while ($w.Elapsed.TotalSeconds -lt 6 -and (SvcQ) -notmatch 'does not exist') { Start-Sleep -Milliseconds 300 }
        Lg ('after stop/unload: [' + (SvcQ) + ']')
        & "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
        $w.Restart(); while ($w.Elapsed.TotalSeconds -lt 6 -and (SvcQ) -notmatch 'does not exist') { Start-Sleep -Milliseconds 300 }
        Lg ('after delete: [' + (SvcQ) + ']')
    }
    $pre = Dse '22'
    Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
    if ($pre -notmatch '^0*0$') { $null = Kdu @('-prv', '20', '-dse', '0'); Start-Sleep -Milliseconds 400 }
    & "$env:SystemRoot\system32\sc.exe" create apexdrv type= kernel start= demand binPath= $sys 2>&1 | Out-Null
    & "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Lg ('svc after start: ' + (SvcQ))
    $null = Kdu @('-prv', '20', '-dse', '22')
    Start-Sleep -Milliseconds 300
    $q = SvcQ
}
$six = Dse '22'; Lg ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
if ($q -notmatch 'RUNNING' -or $six -notmatch '^0*16$') { Lg 'RESULT: FAIL - reload did not hold (svc/dse), not arming'; Emit; exit 1 }
Lg 'ARMED - driver RUNNING, dse 0x16 verified - launch the game now'
$sw = [Diagnostics.Stopwatch]::StartNew()
$tp = 0
while ($sw.Elapsed.TotalMinutes -lt 15 -and -not $tp) { Start-Sleep -Milliseconds 250; $g = @(Get-Process r5apex_dx12 -EA 0); if ($g.Count) { $tp = $g[0].Id } }
if (-not $tp) { Lg 'RESULT: NO-OP - no game in 15 min (driver left RUNNING, dse 0x16)'; Emit; exit 3 }
Lg ('pid=' + $tp + ' - holding 1000 ms')
Start-Sleep -Milliseconds 1000
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $d 'apex_launcher.exe'
$psi.Arguments = ('--kernel-probe --pid=' + $tp + ' --driver "' + $sys + '"')
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
$txt = ''
$psw = [Diagnostics.Stopwatch]::StartNew()
try {
    $pr = [System.Diagnostics.Process]::Start($psi)
    $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync()
    if (-not $pr.WaitForExit(120000)) { Lg 'launcher TIMEOUT'; try { $pr.Kill() } catch { } }
    if ($t1.Wait(4000)) { $txt = $t1.Result }; try { $txt += $t2.Result } catch { }
} catch { Lg ('LAUNCH FAIL ' + $_.Exception.Message) }
foreach ($ln in ($txt -split "`r?`n")) { if ($ln.Trim()) { Lg ('  | ' + $ln.Trim()) } }
$sent = ([bool]($txt -match 'KERNEL context'))
Lg ('probe returned at +' + [int]$psw.Elapsed.TotalMilliseconds + ' ms')
Lg ('svc after probe: [' + (SvcQ) + ']  ioctl_sent=' + $sent)
$died = -1
for ($i = 1; $i -le 60; $i++) { Start-Sleep -Milliseconds 1000; if (-not (Get-Process -Id $tp -EA 0)) { $died = $i; break } }
if (-not $sent) { Lg ('VERDICT: INVALID - probe never reached the IOCTL. game died at +' + $died + ' s (informational only)') }
elseif ($died -gt 0) { Lg ('VERDICT: DEAD +' + $died + ' s after the transient write -> even alloc+write+free with nothing left resident is lethal') }
else { Lg 'VERDICT: ALIVE 60 s after the transient write -> transient kernel write is harmless; the killer is what the map leaves resident in the address space' }
Emit

