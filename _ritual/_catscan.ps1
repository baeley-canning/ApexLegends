# _catscan.ps1 -- definitive DER inventory of a .cat: member identifiers, declared hash OIDs,
# hash values, file names, and whether the engine hashes of given files are literally present.
# No store access, no elevation.  Output -> _ritual\_catscan.txt
param([string]$Cat = 'C:\p26cat\apexdrv_p26.cat',
      [string[]]$File = @('C:\p26cat\apexdrv_build.sys', 'C:\Windows\System32\drivers\apexdrv.sys'))
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_catscan.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }
"=== _catscan $(Get-Date -Format s)  cat=$Cat" | Set-Content -Encoding utf8 $out

function HB([string]$h) { $h = $h -replace '[^0-9A-Fa-f]', ''; $n = $h.Length / 2; $a = New-Object byte[] $n; for ($i = 0; $i -lt $n; $i++) { $a[$i] = [Convert]::ToByte($h.Substring(2 * $i, 2), 16) }; return , $a }
function AllOff([byte[]]$h, [byte[]]$p) {
    $r = New-Object 'System.Collections.Generic.List[int]'
    if (-not $p -or $p.Length -eq 0 -or $h.Length -lt $p.Length) { return $r }
    $lim = $h.Length - $p.Length
    for ($i = 0; $i -le $lim; $i++) {
        if ($h[$i] -ne $p[0]) { continue }
        $j = 1; while ($j -lt $p.Length -and $h[$i + $j] -eq $p[$j]) { $j++ }
        if ($j -eq $p.Length) { [void]$r.Add($i) }
    }
    return $r
}
function SpliceHash([string]$f, [string]$alg) {
    $raw = [IO.File]::ReadAllBytes($f); $len = $raw.Length
    if ($raw[0] -eq 0x4D -and $raw[1] -eq 0x5A) {
        $lf = [BitConverter]::ToInt32($raw, 0x3C); $opt = $lf + 24
        $magic = [BitConverter]::ToUInt16($raw, $opt)
        $dirOff = if ($magic -eq 0x20B) { $opt + 0x70 } else { $opt + 0x60 }
        $chk = $opt + 0x40; $sec = $dirOff + 32
        $cp = [BitConverter]::ToInt32($raw, $sec)
        $vEnd = if ($cp -gt 0 -and $cp -le $len) { $cp } else { $len }
        $ms = New-Object IO.MemoryStream
        $ms.Write($raw, 0, $chk); $ms.Write($raw, $chk + 4, $sec - ($chk + 4)); $ms.Write($raw, $sec + 8, $vEnd - ($sec + 8))
        $d = $ms.ToArray(); $ms.Dispose()
    } else { $d = $raw }
    $a = [Security.Cryptography.HashAlgorithm]::Create($alg)
    try { return ([BitConverter]::ToString($a.ComputeHash($d)) -replace '-', '') } finally { $a.Dispose() }
}

if (-not (Test-Path -LiteralPath $Cat)) { L "MISSING $Cat"; L 'END-catscan'; exit 1 }
$b = [IO.File]::ReadAllBytes($Cat)
L ("cat size = " + $b.Length + "  sha256(cat)=" + (SpliceHash $Cat 'sha256'))

# ---- 1. declared hash algorithms (OIDs) and the octet string that follows each one -----------
$oids = @(
    @{ n = 'sha1';   p = '06052B0E03021A' }
    @{ n = 'sha256'; p = '0609608648016503040201' }
    @{ n = 'md5';    p = '06082A864886F70D0205' }
    @{ n = 'md5-rsa'; p = '06092A864886F70D010104' }
)
L '--- hash-algorithm OIDs in the cat + the value that follows ---'
foreach ($o in $oids) {
    $pb = HB $o.p
    $offs = AllOff $b $pb
    L ("  oid " + $o.n + " @" + ($offs -join ',') + "  count=" + $offs.Count)
    foreach ($off in $offs) {
        $vpos = $off + $pb.Length
        if ($vpos -lt $b.Length -and $b[$vpos] -eq 0x04) {
            $vl = $b[$vpos + 1]
            if ($vl -le 0x40 -and ($vpos + 2 + $vl) -le $b.Length) {
                L ("      value len=" + $vl + "  " + ([BitConverter]::ToString($b, $vpos + 2, $vl) -replace '-', ''))
            } else { L ("      (short-form len=" + $vl + " not bounded)") }
        } else { L '      (no octet string immediately after)' }
    }
}

# ---- 2. every short OCTET STRING of len 20/32/36 (ctx = 6 bytes preceding the 0x04 tag) ------
L '--- octet strings len 20/32/36  (ctx=6 bytes before tag) ---'
for ($i = 0; $i -lt $b.Length - 2; $i++) {
    if ($b[$i] -ne 0x04) { continue }
    $l2 = $b[$i + 1]
    if ($l2 -ne 0x14 -and $l2 -ne 0x20 -and $l2 -ne 0x24) { continue }
    if (($i + 2 + $l2) -gt $b.Length) { continue }
    $ctx = if ($i -ge 6) { ([BitConverter]::ToString($b, $i - 6, 6) -replace '-', '') } else { '------' }
    L ("  @{0,5} len={1,2} ctx={2}  {3}" -f $i, $l2, $ctx, ([BitConverter]::ToString($b, $i + 2, $l2) -replace '-', ''))
}

# ---- 3. CTL member entries: OCTET STRING(tag) + OCTET STRING(member id) -----------------------
L '--- CTL member entries (tag@off idlen id) ---'
foreach ($pt in @('040100', '040101', '040102', '040103')) {
    foreach ($off in (AllOff $b (HB $pt))) {
        $vp = $off + 3
        if ($b[$vp] -eq 0x04) {
            $l3 = $b[$vp + 1]
            if (($vp + 2 + $l3) -le $b.Length) {
                L ("  tag={0} @{1} idlen={2} id={3}" -f $pt.Substring(4, 2), $off, $l3, ([BitConverter]::ToString($b, $vp + 2, $l3) -replace '-', ''))
            }
        }
    }
}

# ---- 4. digest that follows each sha256 AlgorithmIdentifier (skip the NULL params) ------------
L '--- sha256 AlgorithmIdentifier -> following digest ---'
foreach ($off in (AllOff $b (HB '0609608648016503040201'))) {
    $p = $off + 11
    if ($b[$p] -eq 0x05 -and $b[$p + 1] -eq 0x00) { $p += 2 }
    if ($b[$p] -eq 0x04) {
        $l4 = $b[$p + 1]
        if (($p + 2 + $l4) -le $b.Length) { L ("  algoid@{0}  digest len={1}  {2}" -f $off, $l4, ([BitConverter]::ToString($b, $p + 2, $l4) -replace '-', '')) }
    } else { L ("  algoid@{0}  next byte 0x{1:X2} (not an octet string)" -f $off, $b[$p]) }
}

# ---- 5. literal presence of candidate hashes / member names -----------------------------------
L '--- literal presence in the cat ---'
$cand = [ordered]@{}
foreach ($f in $File) { if (Test-Path -LiteralPath $f) { $cand['sha256-engine ' + $f] = SpliceHash $f 'sha256'; $cand['sha1-engine   ' + $f] = SpliceHash $f 'sha1' } }
$cand['sha1(cat)'] = SpliceHash $Cat 'sha1'
$cand['sha256(cat)'] = SpliceHash $Cat 'sha256'
$cand['prefix20-of-sha256-engine'] = '37647B4654AE7F7608D8012A4BAA5AA8FB843552'
foreach ($k in $cand.Keys) {
    $o = AllOff $b (HB $cand[$k])
    L ("  {0} = {1}  offsets=[{2}]" -f $k, $cand[$k], (($o | ForEach-Object { $_ }) -join ','))
}
foreach ($n in @('apexdrv_build.sys', 'apexdrv_sys.sys', 'apexdrv')) {
    $o = AllOff $b ([Text.Encoding]::ASCII.GetBytes($n))
    L ("  name {0} offsets=[{1}]" -f $n, (($o | ForEach-Object { $_ }) -join ','))
}
foreach ($f in $File) { if (Test-Path -LiteralPath $f) { $fi = Get-Item -LiteralPath $f; L ("  file {0} len={1} mtime={2}" -f $f, $fi.Length, $fi.LastWriteTime) } }
$ci = Get-Item -LiteralPath $Cat
L ("  cat len={0} mtime={1}" -f $ci.Length, $ci.LastWriteTime)
L 'END-catscan'
