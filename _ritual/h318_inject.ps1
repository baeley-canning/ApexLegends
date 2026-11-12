# h318_inject.ps1 - inject only, against the gate-armed box (driver `apexdrv` RUNNING from
# h1_dse_host, DSE already back at the boot byte 0x16, game live). No DSE work, no provider load.
# Differs from h317_inject only in the service name it accepts and the driver path it passes, plus
# self-elevation (the launcher needs admin).
param([switch]$elevated)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_inject.out'
$d    = 'C:\Users\Public\p37'
$dll  = 'C:\Users\Public\apexcheat.dll'
$sys  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$pin  = 'E05FE8324148F8BDC944D772AAB76A67089AE152DE2DF61DA7B4D5940440224C'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm -and -not $elevated) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"'), '-elevated') -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Lg '===== h318 inject (game up, apexdrv, DSE 0x16) ====='
$g = @(Get-Process r5apex_dx12 -EA 0)
if (-not $g.Count) { Lg 'RESULT: NO-OP - game not running'; Emit; exit 3 }
$tp = $g[0].Id
Lg ('target pid=' + $tp + ' title=[' + $g[0].MainWindowTitle + '] threads=' + @($g[0].Threads).Count)
$svc = (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim()
Lg ('svc apexdrv: ' + $svc + '  binPath=' + $sys + ' exists=' + (Test-Path $sys))
# absent is fine here: the launcher creates the service itself (it needs DSE 0, which is the state
# Javelin leaves behind once the game is up). Only a present-but-STOPPED service is a failure.
if ($svc -match 'RUNNING') { Lg 'service already RUNNING - launcher will reuse it' }
elseif ($svc -match '1060') { Lg 'service absent - launcher will create it (DSE is off, start can succeed)' }
else { Lg 'RESULT: FAIL - apexdrv present but not RUNNING'; Emit; exit 1 }
$h = (Get-FileHash $dll -Algorithm SHA256).Hash
Lg ('payload sha=' + $h.Substring(0, 16) + $(if ($h -eq $pin) { ' MATCH (audited h314 build)' } else { ' MISMATCH' }))
if ($h -ne $pin) { Lg 'RESULT: FAIL - payload is not the audited image'; Emit; exit 1 }
Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA ('QwenKern\payload_' + $tp + '.log')) -Force -EA 0
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $d 'apex_launcher.exe'
$psi.Arguments = ('--inject --method=kernel --pid ' + $tp + ' --driver "' + $sys + '" --dll "' + $dll + '" --manual-map')
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
Lg ('$ apex_launcher ' + $psi.Arguments)
$txt = ''
try {
    $p = [System.Diagnostics.Process]::Start($psi)
    $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(180000)) { Lg 'launcher TIMEOUT 180s'; try { $p.Kill() } catch { } }
    if (-not $t1.Wait(4000)) { Lg '  (stdout did not close)' } else { $txt = $t1.Result }
    try { $txt += $t2.Result } catch { }
} catch { Lg ('LAUNCH FAIL ' + $_.Exception.Message) }
foreach ($ln in ($txt -split "`r?`n")) { if ($ln.Trim()) { Lg ('  | ' + $ln.TrimEnd()) } }
Start-Sleep -Seconds 2
$alive = [bool](Get-Process -Id $tp -EA 0)
Lg ('post target alive=' + $alive)
$log = Join-Path $env:LOCALAPPDATA ('QwenKern\payload_' + $tp + '.log')
Lg ('oracle=' + $(if (Test-Path $log) { $log + ' (' + (Get-Item $log).Length + 'B)' } else { 'MISSING' }))
if (Test-Path $log) { foreach ($ln in (Get-Content $log -Tail 10)) { Lg ('  o | ' + $ln) } }
$map = ([regex]::Match($txt, 'map: .*')).Value
$flag = ([regex]::Match($txt, 'entryFlag=0x([0-9A-Fa-f]+)')).Groups[1].Value
$res  = ([regex]::Match($txt, 'entryResult=0x([0-9A-Fa-f]+)')).Groups[1].Value
Lg ('parsed map=[' + $map + '] flag=' + $flag + ' entryResult=' + $res)
if ($map -match 'step=0' -and $flag -eq '4871' -and $res -eq '1' -and $alive) {
    Lg 'RESULT: PASS - mapped into the LIVE GAME, entry returned TRUE, target alive'
    Lg 'VERDICT: MAP PASS IN GAME - start _ritual\h2w1_watch.ps1 now'
} elseif (-not $alive) {
    Lg 'RESULT: FAIL - target died during the inject'
    Lg 'VERDICT: FAIL - read the 1000 event and the payload log before another run'
} else {
    Lg 'RESULT: FAIL - map did not complete cleanly'
    Lg 'VERDICT: FAIL - chain, not Javelin'
}
Emit

