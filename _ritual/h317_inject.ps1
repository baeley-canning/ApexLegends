# h317_inject.ps1 - step 2 of the split h317. Runs AFTER h317_arm.ps1 succeeded and AFTER the user
# brought Apex to the menu. Does NO DSE work and NO provider load: the driver is already RUNNING, so
# the only thing that touches the game is the APC + map. That is the variable - "does Javelin react to
# the driver load" is already answered by the arm step surviving; this step answers "does it react to
# an in-process map".
# Leaves everything armed (h317_teardown.ps1 or h317post restores). R5: own output file.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h317_inject.out'
$d    = 'C:\Users\Public\p37'
$dll  = 'C:\Users\Public\apexcheat.dll'
$pin  = 'E05FE8324148F8BDC944D772AAB76A67089AE152DE2DF61DA7B4D5940440224C'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Lg '===== h317 inject ====='
$g = @(Get-Process r5apex_dx12 -EA 0)
if (-not $g.Count) { Lg 'RESULT: NO-OP - r5apex_dx12 not running (no fallback target by design)'; Emit; exit 3 }
$tp = $g[0].Id
Lg ('target pid=' + $tp + ' title=[' + $g[0].MainWindowTitle + '] threads=' + @($g[0].Threads).Count)
$svc = (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim()
Lg ('svc: ' + $svc)
if ($svc -notmatch 'RUNNING') { Lg 'RESULT: FAIL - zapexdrv not RUNNING, run h317_arm.ps1 first'; Emit; exit 1 }
$h = (Get-FileHash $dll -Algorithm SHA256).Hash
Lg ('payload sha=' + $h.Substring(0, 16) + $(if ($h -eq $pin) { ' MATCH (audited h314 build)' } else { ' MISMATCH' }))
if ($h -ne $pin) { Lg 'RESULT: FAIL - payload is not the audited image'; Emit; exit 1 }
Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA ('QwenKern\payload_' + $tp + '.log')) -Force -EA 0
$exe = Join-Path $d 'apex_launcher.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.Arguments = ('--inject --method=kernel --pid ' + $tp + ' --driver ' + (Join-Path $d 'zapexdrv.sys') + ' --dll "' + $dll + '" --manual-map --no-sticky')
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
    Lg 'RESULT: PASS - mapped into the GAME, entry returned TRUE, target still alive'
    Lg 'VERDICT: MAP PASS INTO THE GAME - start h316_watch.ps1 now (rename: h317 watch)'
} elseif (-not $alive) {
    Lg 'RESULT: FAIL - target died during the inject'
    Lg 'VERDICT: FAIL - read the Javelin event (1000) and the payload log before another run'
} else {
    Lg ('RESULT: FAIL - map did not complete cleanly (step/flag/entry above)')
    Lg 'VERDICT: FAIL - chain, not Javelin'
}
Emit
