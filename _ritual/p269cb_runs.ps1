# p269cb: the name blob is not at 0xC3E2 in this dump. Scan the whole file for aligned UTF-16
# printable runs (>=8 chars) and list them with offsets + index. Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cb_runs.txt'
Set-Content -LiteralPath $out -Value ('p269cb ' + (Get-Date -f 'HH:mm:ss'))
$b = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$i = 0; $n = 0
while ($i -lt ($b.Length - 32) -and $n -lt 400) {
    $ok = $b[$i + 1] -eq 0 -and $b[$i] -ge 0x20 -and $b[$i] -lt 0x7F
    if (-not $ok) { $i += 2; continue }
    $t = $i; $sb = New-Object Text.StringBuilder
    while ($t -lt ($b.Length - 1) -and $b[$t + 1] -eq 0 -and $b[$t] -ge 0x20 -and $b[$t] -lt 0x7F) {
        [void]$sb.Append([char]$b[$t]); $t += 2
    }
    if ($sb.Length -ge 8) {
        Add-Content -LiteralPath $out -Value ('[{0}] @0x{1:X5} {2}' -f $n, $i, $sb.ToString())
        $n++
    }
    $i = $t
}
Add-Content -LiteralPath $out -Value ('RUNS=' + $n)
Add-Content -LiteralPath $out -Value 'END'
