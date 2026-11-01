# _catwalk.ps1 -- recursive DER structure walker for a .cat.  Prints the tree so member
# SubjectIdentifiers vs messageDigests vs names are unambiguous.  Optional -Grep <hex> reports
# occurrences with preceding context.  Output -> _ritual\_catwalk.txt
param([string]$Cat = 'C:\p26cat\apexdrv_p26.cat', [int]$From = 0, [int]$To = 0, [int]$Depth = 8, [string]$Grep = '', [string]$Out = '')
$ErrorActionPreference = 'Continue'
$out = if ($Out) { if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $PSScriptRoot $Out } } else { Join-Path $PSScriptRoot '_catwalk.txt' }
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }
"=== _catwalk $(Get-Date -Format s) cat=$Cat from=$From to=$To depth=$Depth" | Set-Content -Encoding utf8 $out
if (-not (Test-Path -LiteralPath $Cat)) { L "MISSING $Cat"; L 'END-catwalk'; exit 1 }
$b = [IO.File]::ReadAllBytes($Cat)
L ('len=' + $b.Length)

function HB([string]$h) { $h = $h -replace '[^0-9A-Fa-f]', ''; $n = $h.Length / 2; $a = New-Object byte[] $n; for ($i = 0; $i -lt $n; $i++) { $a[$i] = [Convert]::ToByte($h.Substring(2 * $i, 2), 16) }; return , $a }
function Oid([int]$p, [int]$l) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append([int]($b[$p] / 40)); [void]$sb.Append('.'); [void]$sb.Append([int]($b[$p] % 40))
    $v = 0
    for ($i = 1; $i -lt $l; $i++) {
        $v = ($v -shl 7) + ($b[$p + $i] -band 0x7F)
        if (-not ($b[$p + $i] -band 0x80)) { [void]$sb.Append('.'); [void]$sb.Append($v); $v = 0 }
    }
    return $sb.ToString()
}
function Tg([byte]$t) {
    $c = switch ($t -band 0xC0) { 0x00 { 'U' } 0x40 { 'A' } 0x80 { 'X' } default { 'P' } }
    $k = if ($t -band 0x20) { 'C' } else { 'P' }
    $n = $t -band 0x1F
    $m = @{ 1 = 'INT'; 2 = 'BITSTR'; 3 = 'BITSTR'; 4 = 'OCTSTR'; 5 = 'NULL'; 6 = 'OID'; 10 = 'ENUM'; 12 = 'UTF8'; 16 = 'SEQ'; 17 = 'SET'; 19 = 'PRINT'; 22 = 'IA5'; 23 = 'UTCTIME'; 24 = 'GENTIME'; 30 = 'BMP' }
    if ($n -eq 0x1F) { return "$c$k-?" }
    $nm = if ($m.ContainsKey($n)) { $m[$n] } else { "T$n" }
    return "$c$k-$nm"
}
function WalkNode([int]$off, [int]$end, [int]$d) {
    $p = $off
    while ($p -lt $end -and $p -lt $b.Length) {
        $t = $b[$p]
        if (($p + 1) -ge $b.Length) { break }
        $l0 = $b[$p + 1]
        if ($l0 -lt 0x80) { $l = $l0; $vp = $p + 2 } else {
            $n = $l0 -band 0x7F
            if ($n -gt 4) { L ("  BADLEN @$p"); break }
            $l = 0; for ($i = 0; $i -lt $n; $i++) { $l = ($l * 256) + $b[$p + 2 + $i] }
            $vp = $p + 2 + $n
        }
        $cons = ($t -band 0x20) -ne 0
        $val = ''
        if ($t -eq 0x06 -and $l -gt 0) { $val = 'OID ' + (Oid $vp $l) }
        elseif (-not $cons -and $l -gt 0 -and $l -le 64) { $val = (([BitConverter]::ToString($b, $vp, $l)) -replace '-', '') }
        elseif (-not $cons -and $l -gt 64) { $val = 'first16=' + (([BitConverter]::ToString($b, $vp, 16)) -replace '-', '') + " ..len=$l" }
        L ("{0}@{1,6} {2,-11} len={3,6} {4}" -f (' ' * ((($d + 1) * 2))), $p, (Tg $t), $l, $val)
        if ($cons -and $d -lt $Depth -and $l -gt 0 -and (($vp + $l) -le $b.Length)) { WalkNode $vp ($vp + $l) ($d + 1) }
        $p = $vp + $l
    }
}
if ($Grep) {
    $g = HB $Grep; $o = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -le $b.Length - $g.Length; $i++) {
        $j = 0; while ($j -lt $g.Length -and $b[$i + $j] -eq $g[$j]) { $j++ }
        if ($j -eq $g.Length) { [void]$o.Add($i) }
    }
    L ("grep {0} -> n={1} offsets=[{2}]" -f $Grep, $o.Count, (($o | ForEach-Object { $_ }) -join ','))
    foreach ($k in $o) { $s = [Math]::Max(0, $k - 14); L ("  occ@{0} ctx={1}" -f $k, (([BitConverter]::ToString($b, $s, $k - $s)) -replace '-', '')) }
}
$f = if ($From) { $From } else { 0 }
$t2 = if ($To) { $To } else { $b.Length }
if ($Grep -and $o -and -not $From -and -not $To) { $f = [Math]::Max(0, $o[0] - 8); $t2 = [Math]::Min($b.Length, $o[0] + 320) }
L ("--- walk [$f,$t2) ---")
WalkNode $f $t2 0
L 'END-catwalk'
