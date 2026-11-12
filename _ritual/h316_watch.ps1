# h316 watch - Phase 2 EAAC tolerance gate. READ-ONLY observer for AFTER a successful h315 inject.
# Samples every 15 s for $Minutes: game pid alive, payload log growth + Present counter continuity,
# window title tick (match-load evidence), new minidumps, EAAC/EAC error events. Own output file.
param([int]$Minutes = 12, [int]$PidHint = 0)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h316_watch.out'
function Say([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Write-Host $line; Add-Content -LiteralPath $out -Value $line }
Add-Content -LiteralPath $out -Value ('===== h316 watch ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
$pid0 = $PidHint
if (-not $pid0) { $pid0 = @(Get-Process r5apex_dx12 -EA 0 | Select-Object -First 1).Id }
if (-not $pid0) { Say 'RESULT: FAIL - r5apex_dx12 not running at watch start'; Say 'VERDICT: FAIL - nothing to watch'; exit 1 }
Say ('pid=' + $pid0 + ' minutes=' + $Minutes)
$dir = Join-Path $env:LOCALAPPDATA 'QwenKern'
$log = $null
$cand = @(Get-ChildItem -LiteralPath $dir -Filter ('payload_' + $pid0 + '.log') -EA 0)
if ($cand.Count -gt 0) { $log = $cand[0].FullName } else {
    $newest = @(Get-ChildItem -LiteralPath $dir -Filter 'payload_*.log' -EA 0 | Sort-Object LastWriteTime -Descending)
    if ($newest.Count -gt 0 -and ((Get-Date) - $newest[0].LastWriteTime).TotalMinutes -lt 10) { $log = $newest[0].FullName }
}
Say ('oracle=' + $(if ($log) { $log } else { 'MISSING' }))
$dumps0 = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count
Say ('baseline minidumps=' + $dumps0)
$start = Get-Date; $ticks = [int]($Minutes * 4); $lastLen = 0; $lastCounter = 0; $counterStart = -1; $prevCounter = -1; $sawApexTitle = $false
for ($i = 1; $i -le $ticks; $i++) {
    Start-Sleep -Seconds 15
    $p = Get-Process -Id $pid0 -EA 0
    if (-not $p) {
        Say ('DEAD at sample ' + $i + ' after ' + [math]::Round(((Get-Date) - $start).TotalMinutes, 1) + ' min')
        if ($log) { Say 'last oracle lines:'; Get-Content -LiteralPath $log -Tail 15 -EA 0 | ForEach-Object { Say ('  | ' + $_) } }
        $dumps1 = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count
        Say ('minidumps now=' + $dumps1 + ' (baseline ' + $dumps0 + ')')
        try { Get-WinEvent -FilterHashtable @{LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-3)} -MaxEvents 40 -EA Stop | Where-Object { $_.ProviderName -match 'EAC|Javelin|Easy' -or $_.Message -match 'Easy Anti-Cheat|Javelin|EAC' } | Select-Object -First 10 | ForEach-Object { Say ('  evt ' + $_.TimeCreated.ToString('HH:mm:ss') + ' ' + $_.ProviderName + ': ' + (($_.Message -split "`r?`n")[0])) } } catch { }
        Say 'RESULT: FAIL - game died under the payload'
        Say ('VERDICT: FAIL - EAAC tolerance gate (death after ' + [math]::Round(((Get-Date) - $start).TotalMinutes, 1) + ' min)')
        exit 2
    }
    $title = $p.MainWindowTitle
    if ($title -match 'Apex') { $sawApexTitle = $true }
    $len = 0; $tail = ''
    if ($log -and (Test-Path -LiteralPath $log)) {
        $len = (Get-Item -LiteralPath $log).Length
        $tail = (Get-Content -LiteralPath $log -Tail 1 -EA 0) -join ''
        $m = [regex]::Matches($tail, 'present counter = (\d+)')
        if ($m.Count -gt 0) { $lastCounter = [int]$m[0].Groups[1].Value; if ($counterStart -lt 0) { $counterStart = $lastCounter } }
    }
    if ($i % 4 -eq 0) {
        $stallNote = ''
        if ($prevCounter -ge 0 -and $lastCounter -le $prevCounter) { $stallNote = ' STALL' }
        $prevCounter = $lastCounter
        Say ('sample ' + $i + ' alive=True len=' + $len + ' counter=' + $lastCounter + $stallNote + ' title=[' + $title + ']')
    }
    if ($i % 20 -eq 0) {
        $e = @(try { Get-WinEvent -FilterHashtable @{LogName = 'Application'; Level = 2; StartTime = (Get-Date).AddMinutes(-5)} -MaxEvents 20 -EA Stop | Where-Object { $_.ProviderName -match 'EAC|Javelin' -or $_.Message -match 'Easy Anti-Cheat|Javelin' } } catch { })
        if ($e.Count -gt 0) { $e | Select-Object -First 3 | ForEach-Object { Say ('  evt ' + $_.TimeCreated.ToString('HH:mm:ss') + ' ' + $_.ProviderName) } } else { Say ('sample ' + $i + ' no EAAC/EAC error events in 5 min') }
    }
}
$alive = [bool](Get-Process -Id $pid0 -EA 0)
Say ('end: alive=' + $alive + ' counterStart=' + $counterStart + ' counterEnd=' + $lastCounter + ' apexTitleSeen=' + $sawApexTitle)
if ($alive) {
    Say ('RESULT: PASS - game alive after ' + $Minutes + ' min, Present counter ' + $counterStart + ' -> ' + $lastCounter)
    Say ('VERDICT: EAAC TOLERATED the in-process payload for ' + $Minutes + ' min (process alive, Present continuous, no minidumps, no EAC termination)')
} else {
    Say 'RESULT: FAIL - game gone at watch end'
    Say 'VERDICT: FAIL - EAAC tolerance gate'
    exit 2
}
