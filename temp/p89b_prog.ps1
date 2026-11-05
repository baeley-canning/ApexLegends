$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Location -LiteralPath $repo
$o = 'C:\Users\New User\AppData\Local\Temp\_prog_report.txt'
$p = 'temp\_p85_prog.txt'
Remove-Item -LiteralPath $o -ErrorAction SilentlyContinue
$all = @(Get-Content -LiteralPath $p -ErrorAction SilentlyContinue)
"total_lines=$($all.Count)" | Out-File -LiteralPath $o -Encoding utf8
$i = 0
$marks = @()
foreach ($ln in $all) {
  $i++
  if ($ln -match 'PIDSCANEND') { $marks += $i }
}
"pidscandend_lines=$($marks -join ',' )" | Out-File -LiteralPath $o -Append -Encoding utf8
$pidat = @($all | Where-Object { $_ -match 'pid@' })
"pid_at_lines=$($pidat.Count)" | Out-File -LiteralPath $o -Append -Encoding utf8
'--- last 14 lines mentioning pid@/PIDSCANEND/control/dtb ---' | Out-File -LiteralPath $o -Append -Encoding utf8
($all | Where-Object { $_ -match 'pid@|PIDSCANEND|control page|dtb=|RAMMAP|pid scan:' } | Select-Object -Last 14) | Out-File -LiteralPath $o -Append -Encoding utf8
'--- distinct hit PA high nibbles (page map) ---' | Out-File -LiteralPath $o -Append -Encoding utf8
($pidat | ForEach-Object { ($_ -split 'pid@')[1] } | ForEach-Object { ($_ -split ' ')[0] } |
  ForEach-Object { if ($_ -match '^(0x[0-9a-f])') { $matches[1] } } | Group-Object |
  Sort-Object Name | ForEach-Object { "  {0} x{1}" -f $_.Name, $_.Count }) | Out-File -LiteralPath $o -Append -Encoding utf8
