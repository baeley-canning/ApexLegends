# p269bk: p2 is a faulting RIP whose low 12 bits are constant (0x5B8). image base = p2-0x5B8.
# A loaded driver's KLDR_DATA_TABLE_ENTRY holds that base; find the qword and read the
# UTF-16 name nearby. Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bk_base.txt'
Set-Content -LiteralPath $out -Value ('p269bk ' + (Get-Date -f 'HH:mm:ss'))
foreach ($f in Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps' -Filter *.dmp) {
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $p2 = [BitConverter]::ToUInt64($b, 0x48)
    $base = $p2 - 0x5B8
    $pat = [BitConverter]::GetBytes($base)
    Add-Content -LiteralPath $out -Value ('== ' + $f.Name + ' p2=0x' + $p2.ToString('X') + ' base=0x' + $base.ToString('X'))
    $n = 0
    for ($i = 0; $i -lt ($b.Length - 16); $i++) {
        if ($b[$i] -ne $pat[0]) { continue }
        $ok = $true
        for ($k = 1; $k -lt 8; $k++) { if ($b[$i + $k] -ne $pat[$k]) { $ok = $false; break } }
        if (-not $ok) { continue }
        $n++
        # scan +-0x200 for a UTF-16 "*.sys" name
        $name = ''
        $s = [Math]::Max(0, $i - 0x200); $e = [Math]::Min($b.Length - 2, $i + 0x200)
        $chunk = $b[$s..$e]
        $u = [Text.Encoding]::Unicode.GetString($chunk) -replace '[^\x20-\x7E]', "`u{00}" 
        $m = [regex]::Matches($u, '[\x20-\x7E]{3,60}\.sys')
        if ($m.Count) { $name = ($m | ForEach-Object { $_.Value }) -join '|' }
        Add-Content -LiteralPath $out -Value ('  hit@0x' + $i.ToString('X') + ' name=' + $name)
        if ($n -ge 12) { break }
    }
    if ($n -eq 0) { Add-Content -LiteralPath $out -Value '  base qword not found (not resident in dump)' }
}
Add-Content -LiteralPath $out -Value 'END'
