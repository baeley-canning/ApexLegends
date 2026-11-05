# p44h segment launcher: stage p44h_scan.ps1 elevated for one explicit range.
# The scan is pure read and one-variable (range), so each segment is its own run.
# Usage: powershell -File C:\Users\New User\OneDrive\Desktop\cheating\temp\p44h_go.ps1 <lo> <hi>
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p44h_go.txt'
function W($t) { ((Get-Date -f 'HH:mm:ss'), $t -join '  ') | Out-File -Append -Encoding utf8 $o }
if ($args.Count -lt 2) { W 'need lo hi'; exit 4 }
$lo = [string]$args[0]; $hi = [string]$args[1]
$g = Get-Process -Id 17584 -EA 0
W ('launch lo=' + $lo + ' hi=' + $hi + ' game_alive=' + [bool]$g)
if (-not $g) { W 'ABORT game gone'; exit 2 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p44h_scan.ps1', '--pid=17584', ('--lo=' + $lo), ('--hi=' + $hi), '--want=3', '--max-s=240'
W ('LAUNCHED pid=' + $r.Id)
$r.Id
