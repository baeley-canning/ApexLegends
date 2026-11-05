# p44g_watch.ps1 -- read-only watcher for the p44g game-up step (R6: scripted, own output).
# Polls (5 s) for r5apex_dx12, then EAAC (EAAntiCheat* / EACefSubProcess*), logs transitions + settle seconds
# to _ritual\p44g_watch.txt. Reads system state only; its only write is this file.
# Breaks when EAC has been up 120 s (decoys planted, lobby reachable), or 20 min cap.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out  = Join-Path $repo '_ritual\p44g_watch.txt'
"=== p44g_watch $(Get-Date -Format o) ===" | Set-Content -Encoding utf8 $out
function L([string]$t) { ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $t) | Out-File -Append -Encoding utf8 $out }
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L "watcher pid=$PID elevated=$elev"
$deadline = (Get-Date).AddMinutes(20)
$gp = 0; $eacT0 = $null; $lastN = ''
while ((Get-Date) -lt $deadline) {
  $g = Get-Process -Name r5apex_dx12 -EA 0 | Select-Object -First 1
  if ($g -and $gp -ne $g.Id) {
    $gp = $g.Id
    L ("GAME pid=$gp start=" + $g.StartTime.ToString('HH:mm:ss'))
  }
  if (-not $g -and $gp) { L "GAME GONE pid=$gp"; $gp = 0; $eacT0 = $null }
  $eac = @(Get-Process -Name EAAntiCheat*,EACefSubProcess* -EA 0)
  if ($gp -and $eac.Count -and -not $eacT0) {
    $eacT0 = Get-Date
    L ("EAC " + (($eac | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Id }) -join ' '))
    $svc = (sc.exe query gdrv3 | Select-String 'STATE').ToString().Trim()
    $w = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 1 -EA 0)
    L ("pre-state gdrv3: $svc; last WHEA: " + $(if ($w.Count -and $w[0]) { $w[0].TimeCreated.ToString('HH:mm:ss') } else { 'none' }))
  }
  if ($eacT0) {
    $s = [int]((Get-Date) - $eacT0).TotalSeconds
    if ($s -ge 120) { L "SETTLED settle_s=$s game_pid=$gp"; break }
    $n = "game_pid=$gp eac_procs=$($eac.Count) settle_s=$s"
    if ($n -ne $lastN -and (($s % 30) -lt 6)) { L $n; $lastN = $n }
  }
  Start-Sleep -Seconds 5
}
L 'watch end'
