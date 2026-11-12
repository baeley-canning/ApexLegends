# h320_fire_kprobe.ps1 - h320: the REAL transient probe.  h319 ran the user-mode ACG harness
# (--probe) and never issued a kernel IOCTL; this one runs --kernel-probe (Q10 IOCTL: lookup ->
# open -> alloc 4K RW -> write 1 byte -> MEM_RELEASE free -> PEB copy), so the variable
# "transient foreign kernel write, nothing resident" is finally measured.
# Elevated only (SCM), so the script self-elevates.  It reloads the driver itself (DSE 0 ->
# start -> DSE 22 verified, the h318_reload recipe) because the probe stops+deletes the
# service when it is done.  ONE game launch, 15 min fuse, 60 s timed liveness watch.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h320_fire_kprobe.out'
$d    = 'C:\Users\Public\p37'
$sys  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
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
Lg '===== h320 kernel transient probe (elevated, 15 min fuse) ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=[' + (SvcQ) + '] drv sha=' + (Get-FileHash $sys -Algorithm SHA256).Hash.Substring(0, 16))
if ((Get-FileHash $sys -Algorithm SHA256).Hash -ne '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C') { Lg 'RESULT: FAIL - staged image is not the v14 build'; Emit; exit 1 }
# R4: reload dance owns its restore - DSE 0 for the start, straight back to the boot byte 0x16.
$o = Kdu @('-prv', '20', '-dse'); $pre = if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
if ($pre -notmatch '^0*0$') { Lg ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']'); Start-Sleep -Milliseconds 400 }
& "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" create apexdrv type= kernel start= demand binPath= $sys 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
Start-Sleep -Seconds 2
$q = SvcQ; Lg ('svc after start: ' + $q)
Lg ('dse->22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']'); Start-Sleep -Milliseconds 400
$c2 = Kdu @('-prv', '20', '-dse', '22'); $six = if ($c2 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
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
Lg ('probe returned at +' + [int]$psw.Elapsed.TotalMilliseconds + ' ms')
Lg ('svc after probe: [' + (SvcQ) + ']')
$died = -1
for ($i = 1; $i -le 60; $i++) { Start-Sleep -Milliseconds 1000; if (-not (Get-Process -Id $tp -EA 0)) { $died = $i; break } }
if ($died -gt 0) { Lg ('VERDICT: DEAD +' + $died + ' s after probe -> even a transient kernel write is lethal (residency NOT the variable)') }
else { Lg 'VERDICT: ALIVE 60 s after probe -> transient kernel write is safe; kill is tied to what the map LEAVES RESIDENT (or the entry call)' }
Emit
