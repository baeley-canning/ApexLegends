$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_wr4.txt'
Remove-Item -LiteralPath $r -EA 0
# drv64.dll stores the provider rows as UTF-16; the ASCII scan in p269dd could never hit.
$b = [IO.File]::ReadAllBytes('C:\p37vm\payload\drv64.dll')
$s = [Text.Encoding]::Unicode.GetString($b)
('len={0} unicode_len={1}' -f $b.Length, $s.Length) | Add-Content -LiteralPath $r
foreach ($t in 'WinRing0x64', 'MmMapIoSpace', 'AsIO3') {
    $hits = 0; $i = 0; $first = -1
    while (($i = $s.IndexOf($t, $i)) -ge 0) { if ($first -lt 0) { $first = $i }; $hits++; $i++ }
    ('{0,-16} n={1} first_char={2} first_byte={3}' -f $t, $hits, $first, ($first * 2)) | Add-Content -LiteralPath $r
}
$i = $s.IndexOf('MmMapIoSpace')
if ($i -ge 0) {
    # 2 bytes per char: byte offset = i*2. Show the row it sits in.
    $ctx = $s.Substring([Math]::Max(0, $i - 120), 300) -replace '[^\x20-\x7E]', '.'
    Add-Content -LiteralPath $r ('ctx@' + ($i * 2) + ': ' + $ctx)
} else {
    Add-Content -LiteralPath $r 'MmMapIoSpace absent as UTF-16 too - db rows carry no import names'
}
'done' | Add-Content -LiteralPath $r
