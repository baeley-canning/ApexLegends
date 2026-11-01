$ErrorActionPreference = 'Continue'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = Join-Path $r 'p13_status.txt'
if (Test-Path $o) { Remove-Item $o -Force }
function W($s) { $s | Add-Content -LiteralPath $o }

W ('=== p13 status ' + (Get-Date) + ' ===')
W ('shellAdmin=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

W ''
W '--- probe processes ---'
Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
  W ("pid=$($_.Id) start=$($_.StartTime.ToString('HH:mm:ss')) mb=$([int]($_.WorkingSet64 / 1MB))")
}

W ''
W '--- p13 artefacts ---'
Get-ChildItem -LiteralPath $r -Filter 'p13_*' | Sort-Object Name | ForEach-Object {
  W ("$($_.Name)`t$($_.Length)`t$($_.LastWriteTime.ToString('HH:mm:ss'))")
}

W ''
W '--- string-phase progress ---'
foreach ($t in 'launcher', 'gameservice', 'launcherdll', 'gameservicedll') {
  $f = Join-Path $r ("p13_str_$t.txt")
  if (Test-Path $f) {
    $c = Get-Content -LiteralPath $f
    W ("$t : strprobe=$($c.Count) lines; tail=")
    W (($c | Select-Object -Last 3) -join ' || ')
  } else { W "$t : strprobe=absent" }
  $g = Join-Path $r ("p13_strall_$t.txt")
  if (Test-Path $g) { W "$t : fulldump=$((Get-Item $g).Length) bytes" } else { W "$t : fulldump=absent" }
}

W ''
W '--- EA Desktop launcher log cert/policy lines ---'
$lg = 'C:\ProgramData\EA Desktop\Logs\EALauncher.log'
if (Test-Path $lg) {
  W ('logsize=' + (Get-Item $lg).Length)
  $hit = Select-String -LiteralPath $lg -Pattern 'cert|root|trust|Attest|sign|Polic|Integrity|Violation|denied|Secure|block' -AllMatches
  W ('matches=' + @($hit).Count)
  $hit | Select-Object -First 70 | ForEach-Object { W ("$($_.LineNumber): " + $_.Line.Trim()) }
} else { W 'launcher log absent' }
