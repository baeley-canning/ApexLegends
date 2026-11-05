$c = Import-Csv -LiteralPath 'C:\p37vm\payload\list.csv'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_ids.txt'
Remove-Item -LiteralPath $r -EA 0
'total=' + $c.Count | Add-Content -LiteralPath $r
foreach ($id in 4, 13, 22, 30, 32, 33, 38, 39, 40, 41) {
    $row = $c | Where-Object { $_.ProviderId -eq $id }
    if ($row) { ('id={0} drv={1} min={2} max={3} flags=0x{4}' -f $id, $row.DriverName, $row.MinNtBuild, $row.MaxNtBuild, $row.Flags) | Add-Content -LiteralPath $r }
    else { ('id={0} MISSING' -f $id) | Add-Content -LiteralPath $r }
}
Add-Content -LiteralPath $r '--- all ids/names ---'
$c | ForEach-Object { $_.ProviderId + ' ' + $_.DriverName } | Add-Content -LiteralPath $r
