# brute4.ps1 - enumerate plausible "catalog hash" transforms for a PE, and report any
# that reproduces the ground-truth API hash. Ground truth (sha1 + sha256) comes from
# catdef.txt / CryptCATAdminCalcHashFromFileHandle2 itself.
$dir = $PSScriptRoot
$out = Join-Path $dir 'brute4.txt'
$targets = @{
  (Join-Path $dir '_p25h_S6lan.sys')                              = '23C73EF919F18ECF9855331CF2563D3A15AF52BC|37647B4654AE7F7608D8012A4BAA5AA8FB843552F6F053C2549ECE167D4C6EE8'
  'C:\WINDOWS\System32\drivers\gdrv3.sys'                         = 'C4C347210FADCE1EA25D621B2EC7D2365596861D|8BB3CEAB17A11A1FD7F5730B186DE382915A49D4EA4367B371802852969CD23D'
}
"brute4 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
public static class B4 {
    public static string Sha1(byte[] d)   { return BitConverter.ToString(SHA1.Create().ComputeHash(d)).Replace("-",""); }
    public static string Sha256(byte[] d) { return BitConverter.ToString(SHA256.Create().ComputeHash(d)).Replace("-",""); }
    public class Sec { public string nm; public uint vs, va, srsd, prd; public int idx; }
    public static int Lf(byte[] r) { return BitConverter.ToInt32(r, 0x3C); }
    public static List<Sec> Secs(byte[] r) {
        int lf = Lf(r); int n = BitConverter.ToUInt16(r, lf + 6); int soh = BitConverter.ToUInt16(r, lf + 20);
        var l = new List<Sec>();
        for (int i = 0; i < n; i++) {
            int o = lf + 24 + soh + i * 40;
            var s = new Sec();
            s.nm = Encoding.ASCII.GetString(r, o, 8).TrimEnd('\0'); s.idx = i;
            s.vs = BitConverter.ToUInt32(r, o + 8); s.va = BitConverter.ToUInt32(r, o + 12);
            s.srsd = BitConverter.ToUInt32(r, o + 16); s.prd = BitConverter.ToUInt32(r, o + 20);
            l.Add(s);
        }
        return l;
    }
    public static byte[] Cat(params byte[][] parts) {
        var ms = new MemoryStream();
        foreach (var p in parts) if (p != null && p.Length > 0) ms.Write(p, 0, p.Length);
        return ms.ToArray();
    }
    public static byte[] Slice(byte[] r, long off, long n) {
        if (off < 0) off = 0; if (off > r.Length) off = r.Length;
        if (n < 0) n = 0; if (off + n > r.Length) n = r.Length - off;
        byte[] b = new byte[n]; Array.Copy(r, off, b, 0, n); return b;
    }
    public static byte[] Zeros(long n) { return new byte[n < 0 ? 0 : n]; }
    // NOTE: opt = lf + 24 (not +SizeOfOptionalHeader); checksum = opt+0x40, cert dir = opt+0x70+32
    public static byte[] ZeroChecksum(byte[] b, int lf, int soh) { int c = lf + 24 + 0x40; if (c + 4 <= b.Length) for (int i = 0; i < 4; i++) b[c + i] = 0; return b; }
    public static byte[] ZeroSecDir(byte[] b, int lf, int soh)   { int c = lf + 24 + 0x70 + 4 * 8; if (c + 8 <= b.Length) for (int i = 0; i < 8; i++) b[c + i] = 0; return b; }
}
'@

$raw = [byte[]][IO.File]::ReadAllBytes((Join-Path $dir '_p25h_S6lan.sys'))
$lf  = [B4]::Lf($raw)
$soh = [BitConverter]::ToUInt16($raw, $lf + 20)
$secs = [B4]::Secs($raw)
$len  = $raw.Length
$cp   = [BitConverter]::ToInt32($raw, $lf + 24 + 0x70 + 4 * 8)
$sohH = [BitConverter]::ToUInt32($raw, $lf + 24 + 0x3C)
$t    = $targets[(Join-Path $dir '_p25h_S6lan.sys')] -split '\|'
Add-Content -Encoding utf8 $out ("S6lan lf=$lf sizeOfOptionalHeader=$soh sizeOfHeaders=$sohH cp=$cp len=$len")
Add-Content -Encoding utf8 $out ("targets sha1=$($t[0]) sha256=$($t[1])")

# ---- build candidate buffers ----
$orders = @{ table = ($secs | Sort-Object idx); byprd = ($secs | Sort-Object prd); byva = ($secs | Sort-Object va) }
$sizeSrcs = @{ srsd = 'srsd'; vsize = 'vs'; minSrsdVsize = 'min' }
$starts = @{ none = 0; lf = $lf; hdr = ($lf + 24 + $soh); soheaders = $sohH }
$tailModes = @{ none = 'n'; pad = 'p' }
$zeroModes = @{ plain = 0; zc = 1; zs = 2; zczs = 3 }
$gapModes = @{ none = 0; vaGap = 1 }

$hits = 0; $tested = 0
foreach ($oKey in $orders.Keys) { foreach ($sKey in $sizeSrcs.Keys) { foreach ($stKey in $starts.Keys) {
foreach ($tailKey in $tailModes.Keys) { foreach ($zmKey in $zeroModes.Keys) { foreach ($gmKey in $gapModes.Keys) {
    foreach ($limitKey in @('cp','len','secend')) {
        $parts = New-Object System.Collections.Generic.List[byte[]]
        $parts.Add([B4]::Slice($raw, 0, $starts[$stKey]))
        $cursor = [int]$starts[$stKey]
        $ok = $true
        foreach ($s in $orders[$oKey]) {
            if ($s.prd -lt 0 -or $s.prd -ge $len) { $ok = $false; break }
            $n = $s.srsd
            if ($sKey -eq 'vs')      { $n = $s.vs }
            if ($sKey -eq 'min')     { $n = [Math]::Min($s.vs, $s.srsd) }
            if ($gmKey -eq 'vaGap' -and $cursor -gt 0 -and $s.prd -gt $cursor) { }   # gap handled via raw slice already
            $parts.Add([B4]::Slice($raw, $s.prd, $n))
        }
        if (-not $ok) { continue }
        $lastEnd = ($orders[$oKey] | ForEach-Object { [int]($_.prd + $_.srsd) } | Measure-Object -Maximum).Maximum
        $lim = $cp; if ($limitKey -eq 'len') { $lim = $len }; if ($limitKey -eq 'secend') { $lim = $lastEnd }
        if ($tailModes[$tailKey] -eq 'p' -and $lastEnd -lt $lim) { $parts.Add([B4]::Slice($raw, $lastEnd, $lim - $lastEnd)) }
        $buf = [B4]::Cat($parts.ToArray())
        if ($zmKey -eq 'zc' -or $zmKey -eq 'zczs') { $buf = [B4]::ZeroChecksum($buf, $lf, $soh) }
        if ($zmKey -eq 'zs' -or $zmKey -eq 'zczs') { $buf = [B4]::ZeroSecDir($buf, $lf, $soh) }
        $tested++
        $h1 = [B4]::Sha1($buf); $h2 = [B4]::Sha256($buf)
        $m = @(); if ($h1 -eq $t[0]) { $m += 'SHA1' }; if ($h2 -eq $t[1]) { $m += 'SHA256' }
        if ($m.Count) { $hits++; Add-Content -Encoding utf8 $out ("HIT {$($m -join '+')} order=$oKey size=$sKey start=$stKey tail=$tailKey zero=$zmKey limit=$limitKey buflen=$($buf.Length)") }
    }
}
}}}}}
Add-Content -Encoding utf8 $out "tested=$tested hits=$hits"
Add-Content -Encoding utf8 $out 'DONE-brute4'
'brute4 done'
