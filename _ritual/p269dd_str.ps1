$p = 'C:\p37vm\payload\drv64.dll'
$b = [IO.File]::ReadAllBytes($p)
$s = [Text.Encoding]::ASCII.GetString($b)
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269dd_str.txt'
Remove-Item -LiteralPath $out -EA 0
"len={0}" -f $b.Length | Add-Content -LiteralPath $out
foreach ($t in 'MmMapIoSpace', 'WinRing0x64.sys', 'MmGetVirtualForPhysical', 'ZwMapViewOfSection') {
    $idx = @(); $i = 0
    while (($i = $s.IndexOf($t, $i)) -ge 0 -and $idx.Count -lt 8) { $idx += $i; $i += $t.Length }
    "{0,-24} n={1} at={2}" -f $t, $idx.Count, ($idx -join ',') | Add-Content -LiteralPath $out
}
$i = $s.IndexOf('MmMapIoSpace')
if ($i -ge 0) {
    $ctx = $s.Substring([Math]::Max(0, $i - 260), 520) -replace '[^\x20-\x7E]', '.'
    Add-Content -LiteralPath $out ('ctx: ' + $ctx)
}
'done' | Add-Content -LiteralPath $out

