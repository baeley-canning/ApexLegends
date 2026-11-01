$ErrorActionPreference = 'Stop'
$o = 'c:\Users\New User\OneDrive\Desktop\cheating\_catmemb.txt'
Set-Content -LiteralPath ($o + '.start') -Value (Get-Date -Format s) -Encoding utf8
$L = New-Object 'System.Collections.Generic.List[string]'
function Log($s) { [void]$L.Add([string]$s) }
function Hx([byte[]]$b) { return ([BitConverter]::ToString($b)).Replace('-', '') }
function Sha([byte[]]$b, [string]$alg) {
    $h = [System.Security.Cryptography.HashAlgorithm]::Create($alg)
    try { return (Hx $h.ComputeHash($b)) } finally { $h.Dispose() }
}
# same semantics as cateng.ps1 DigestFile: drop checksum + certificate table
function Engine([string]$f, [string]$alg) {
    $b = [IO.File]::ReadAllBytes($f)
    if ($b.Length -lt 0x100) { return (Sha $b $alg) }
    $lf = [BitConverter]::ToInt32($b, 0x3C)
    if ($lf -le 0 -or ($lf + 0x100) -gt $b.Length) { return (Sha $b $alg) }
    $magic = [BitConverter]::ToUInt16($b, $lf + 24)
    $ck = $lf + 24 + 64
    if (($ck + 4) -le $b.Length) { 0..3 | ForEach-Object { $b[$ck + $_] = 0 } }
    $dd = if ($magic -eq 0x20B) { $lf + 24 + 112 } else { $lf + 24 + 96 }
    $sp = $dd + 4 * 8
    $certVa = 0; $certSize = 0
    if (($sp + 8) -le $b.Length) {
        $certVa = [BitConverter]::ToInt32($b, $sp); $certSize = [BitConverter]::ToInt32($b, $sp + 4)
        0..7 | ForEach-Object { $b[$sp + $_] = 0 }
    }
    $len = $b.Length
    if ($certSize -gt 0 -and $certVa -gt 0 -and $certVa -lt $b.Length) { $len = $certVa }
    $sub = New-Object byte[] $len; [Array]::Copy($b, $sub, $len)
    return (Sha $sub $alg)
}
try {
    Log ('catmemb ' + (Get-Date -Format s))
    $files = @(
        'C:\p26cat\real\apexdrv_build.sys',
        'C:\p26cat\real\apexdrv_sys.sys',
        'C:\p26cat\apexdrv_build.sys',
        'C:\p26cat\apexdrv_sys.sys',
        'C:\p26cat\p26probe.bin',
        (Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'))
    $pats = New-Object 'System.Collections.Generic.List[object]'
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) { Log ('MISSING ' + $f); continue }
        $rb = [IO.File]::ReadAllBytes($f)
        Log ('=== FILE ' + $f + '  len=' + $rb.Length)
        foreach ($a in @('sha1', 'sha256')) {
            $pl = Sha $rb $a; $en = Engine $f $a
            Log ('  ' + $a + ' plain =' + $pl + '  plainEqEngine=' + ($pl -eq $en))
            Log ('  ' + $a + ' engine=' + $en)
            [void]$pats.Add(@(($f + '::' + $a + '::plain'), $pl))
            [void]$pats.Add(@(($f + '::' + $a + '::engine'), $en))
        }
    }
    $oids = @(
        @('sha1-OID', '06092B0E03021A'),
        @('sha256-OID', '0609608648016503040201'),
        @('SPC_PE_IMAGE_DATA_OBJID', '060A2B06010401823702010F'),
        @('SPC_CAB_DATA_OBJID', '060A2B060104018237020119'),
        @('SPC_INDIRECT_DATA_OBJID', '060A2B060104018237020104'))
    foreach ($c in (Get-ChildItem -LiteralPath 'C:\p26cat' -Filter '*.cat' -ErrorAction SilentlyContinue)) {
        $cb = [IO.File]::ReadAllBytes($c.FullName)
        $hx = Hx $cb
        Log ('=== CAT ' + $c.FullName + '  len=' + $cb.Length + '  mtime=' + $c.LastWriteTime.ToString('s'))
        foreach ($p in $pats) { Log ('  memberHash ' + $p[0] + ' @ ' + $hx.IndexOf($p[1])) }
        foreach ($od in $oids) { Log ('  oid ' + $od[0] + ' @ ' + $hx.IndexOf($od[1])) }
    }
    Log 'DONE'
} catch {
    Log ('ERR ' + $_.Exception.GetType().FullName + ' :: ' + $_.Exception.Message)
    Log ($_.ScriptStackTrace)
}
$L | Set-Content -LiteralPath $o -Encoding utf8

