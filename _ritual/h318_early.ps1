# h318_early.ps1 - fire the inject the instant a NEW r5apex_dx12 appears, not after the lobby.
# Rationale: the map dies at step 5 (alloc, 0xC000000D) once the game is fully initialised, while the
# identical map into notepad passes with the same driver in the same minute. So the game process gets
# hardened during start-up and the window before that is what we want (user's point: inject first).
# Requires apexdrv RUNNING. Polls at 150 ms, ignores any pid listed at start, logs wall times.
param([switch]$elevated)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_early.out'
$d    = 'C:\Users\Public\p37'
$dll  = 'C:\Users\Public\apexcheat.dll'
$sys  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm -and -not $elevated) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"'), '-elevated') -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Lg '===== h318 early inject ====='
$svc = (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim()
Lg ('apexdrv: ' + $svc)
if ($svc -notmatch 'RUNNING') { Lg 'RESULT: FAIL - driver not RUNNING (run h318_reload first)'; Emit; exit 1 }
$known = @(Get-Process r5apex_dx12 -EA 0 | ForEach-Object { $_.Id })
Lg ('preexisting pids=[' + ($known -join ',') + '] waiting for a new one (up to 180 s)')
$sw = [Diagnostics.Stopwatch]::StartNew()
$tp = 0
while ($sw.Elapsed.TotalSeconds -lt 180 -and -not $tp) {
    Start-Sleep -Milliseconds 150
    foreach ($p in @(Get-Process r5apex_dx12 -EA 0)) {
        if ($known -notcontains $p.Id) { $tp = $p.Id; Lg ('NEW pid=' + $tp + ' at +' + [math]::Round($sw.Elapsed.TotalSeconds, 2) + 's'); break }
    }
}
if (-not $tp) { Lg 'RESULT: NO-OP - no new game process in 180 s'; Emit; exit 3 }
Lg 'holding 900 ms before the call (address space needs a moment)'; Start-Sleep -Milliseconds 900
$t0 = $sw.Elapsed.TotalSeconds
# fire at once; a couple of retries only if the very first call loses the race with the loader
for ($k = 1; $k -le 3; $k++) {
    Lg ('inject attempt ' + $k + ' at +' + [math]::Round($sw.Elapsed.TotalSeconds, 2) + 's')
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'apex_launcher.exe'
    $psi.Arguments = ('--inject --method=kernel --pid ' + $tp + ' --driver "' + $sys + '" --dll "' + $dll + '" --manual-map')
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    $txt = ''
    try {
        $pr = [System.Diagnostics.Process]::Start($psi)
        $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync()
        if (-not $pr.WaitForExit(120000)) { Lg 'launcher TIMEOUT'; try { $pr.Kill() } catch { } }
        if ($t1.Wait(4000)) { $txt = $t1.Result }; try { $txt += $t2.Result } catch { }
    } catch { Lg ('LAUNCH FAIL ' + $_.Exception.Message) }
    foreach ($ln in ($txt -split "`r?`n")) { if ($ln.Trim() -match 'map:|delivery:|reason:|\+{3}|SUCCESS') { Lg ('  | ' + $ln.Trim()) } }
    if ($txt -match 'map: .*step=0') { break }
    Start-Sleep -Milliseconds 400
    if (-not (Get-Process -Id $tp -EA 0)) { Lg 'target gone'; break }
}
$alive = [bool](Get-Process -Id $tp -EA 0)
Lg ('post alive=' + $alive + ' elapsed=+' + [math]::Round($sw.Elapsed.TotalSeconds, 2) + 's (inject fired +' + [math]::Round($t0, 2) + 's)')
$log = Join-Path $env:LOCALAPPDATA ('QwenKern\payload_' + $tp + '.log')
Lg ('oracle=' + $(if (Test-Path $log) { 'PRESENT ' + (Get-Item $log).Length + 'B' } else { 'MISSING' }))
if (Test-Path $log) { foreach ($ln in (Get-Content $log -Tail 8)) { Lg ('  o | ' + $ln) } }
Emit



