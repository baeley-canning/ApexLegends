# p53 offline self-test: classifier wiring + window selector against the p52 fixture.
# No game, no elevation, no device.  Proves stage 0 and stage 3 before the live run.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$sc   = Join-Path $repo 'temp\p53_class_selfcheck.txt'
& 'C:\Windows\Temp\p53_class.ps1' -Hits (Join-Path $repo '_ritual\p52_hits.txt') -Out $sc *> (Join-Path $repo 'temp\p53_sc_con.txt')
$rows = @(Select-String -LiteralPath $sc -Pattern '^page=' -EA 0)
Write-Output ('class rows=' + $rows.Count + ' (expect 11)')
$sum = (Select-String -LiteralPath $sc -Pattern '^pages=' -EA 0 | Select-Object -Last 1).Line
Write-Output ('class sum=' + $sum)
. 'C:\Windows\Temp\p53_win.ps1'
$ws = @(Get-P53Windows -ClassFile $sc -Margin 8 -MaxPages 20 -MaxWindows 12)
Write-Output ('windows=' + $ws.Count)
foreach ($w in $ws) { Write-Output ('  w lo=0x{0:x} pages={1} hits={2}' -f $w.lo, $w.pages, $w.hits.Count) }
$tot = 0
foreach ($w in $ws) { $tot += $w.pages }
Write-Output ('pages_total=' + $tot + ' MiB=' + [Math]::Round((($tot * 0x1000) / 1MB), 2))
$fdb = @($ws | Where-Object { $_.page -eq '70711d000' })
Write-Output ('fdb_window=' + $fdb.Count + ' covers_fdb_hits=' + $(if ($fdb.Count) { [bool](($fdb[0].lo -le 0x70711db40) -and (($fdb[0].lo + $fdb[0].pages * 0x1000) -gt 0x70711ddc0)) } else { $false }))
if ($rows.Count -ge 5 -and $ws.Count -ge 1 -and $fdb.Count -eq 1) { Write-Output 'P53_SELFTEST_OK' } else { Write-Output 'P53_SELFTEST_FAIL' }
# arg strings exactly as p53_run.ps1 stage 3 builds them (format/quoting check, nothing executed)
foreach ($w in ($fdb + $ws[0])) {
  $out = Join-Path $repo ('temp\p53_dump_X.txt')
  $hav = @('-u', ('"' + (Join-Path $repo 'ext\p53_padump.py') + '"'), ('--pa=0x{0:x}' -f $w.lo),
           ('--pages=' + $w.pages), ('--label=p' + $w.page), ('"--out=' + $out + '"'))
  foreach ($h in $w.hits) { $hav += ('--hit=0x{0:x}' -f $h) }
  Write-Output ('argv: ' + ($hav -join ' '))
}
