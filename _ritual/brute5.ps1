# brute5.ps1 - DEFINITIVE transform isolation. Uses the API itself as an oracle:
# materialize a candidate buffer to a temp file and ask CryptCATAdminCalcHash* what it
# hashes. Decls mirror catdef.ps1 (CharSet.Unicode REQUIRED, else NTE_BAD_ALGID).
# Targets (ground truth, from catdef.txt): sha1 23C73EF9... / sha256 37647B46...
$dir = $PSScriptRoot
$out = Join-Path $dir 'brute5.txt'
$S = Join-Path $dir '_p25h_S6lan.sys'
$A = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'
"brute5 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
function L($m) { Add-Content -Encoding utf8 $out $m }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class B5 {
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminAcquireContext(out IntPtr h, ref Guid sub, int flags);
    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminCalcHashFromFileHandle(IntPtr hFile, ref int pcb, byte[] pb, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr hAdmin, IntPtr hFile, ref int pcb, byte[] pb, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminReleaseContext(IntPtr h, int flags);
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    static string Hex(byte[] b, int n) { var s = new StringBuilder(); for (int i = 0; i < n; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }
    static string Do(IntPtr h, string path) {
        try {
            using (var fs = File.OpenRead(path)) {
                byte[] buf = new byte[64]; int need = buf.Length;
                if (!CryptCATAdminCalcHashFromFileHandle2(h, fs.SafeFileHandle.DangerousGetHandle(), ref need, buf, 0))
                    return "ERR" + Marshal.GetLastWin32Error();
                return Hex(buf, need);
            }
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
    public static string ApiSha1(string path) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext(out h, ref g, 0)) return "ctxL-ERR" + Marshal.GetLastWin32Error();
        return Do(h, path);
    }
    public static string ApiSha256(string path) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext2(out h, ref g, "SHA256", IntPtr.Zero, 0)) return "ctx2-ERR" + Marshal.GetLastWin32Error();
        return Do(h, path);
    }
}
'@

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;
public static class V5 {
    public static string Hx(byte[] d, string algo) {
        byte[] h = (algo == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d);
        return BitConverter.ToString(h).Replace("-", "");
    }
    public static byte[] Slice(byte[] r, int off, int n) {
        if (off < 0) off = 0; if (off > r.Length) off = r.Length; if (n < 0) n = 0;
        if (off + n > r.Length) n = r.Length - off;
        byte[] b = new byte[n]; Array.Copy(r, off, b, 0, n); return b;
    }
    public static byte[] Cat(params byte[][] p) {
        var ms = new MemoryStream();
        foreach (var x in p) if (x != null) ms.Write(x, 0, x.Length);
        return ms.ToArray();
    }
    public static byte[] Zeros(int n) { return new byte[n < 0 ? 0 : n]; }
    public static byte[] Zero(byte[] b, int off, int n) { for (int i = 0; i < n && off + i < b.Length; i++) b[off + i] = 0; return b; }
    public static byte[] CopyOf(byte[] b) { var c = new byte[b.Length]; Array.Copy(b, c, b.Length); return c; }
}
'@

$rawS = [IO.File]::ReadAllBytes($S)
$rawA = [IO.File]::ReadAllBytes($A)
$lenS = $rawS.Length; $lenA = $rawA.Length
$lf    = [BitConverter]::ToInt32($rawS, 0x3C)
$ohsz  = [BitConverter]::ToUInt16($rawS, $lf + 20)
$opt   = $lf + 24
$sohHd = [BitConverter]::ToUInt32($rawS, $opt + 0x3C)
$chk   = $opt + 0x40
$sec   = $opt + 0x70 + 4 * 8
$cpS   = [BitConverter]::ToInt32($rawS, $sec); $clS = [BitConverter]::ToInt32($rawS, $sec + 4)
$cpA   = [BitConverter]::ToInt32($rawA, $sec); $clA = [BitConverter]::ToInt32($rawA, $sec + 4)
$tS1 = '23C73EF919F18ECF9855331CF2563D3A15AF52BC'
$tS2 = '37647B4654AE7F7608D8012A4BAA5AA8FB843552F6F053C2549ECE167D4C6EE8'
L "S6lan: lf=$lf ohsz=$ohsz sizeOfHeaders=$sohHd chkOff=$chk secOff=$sec cp=$cpS cl=$clS len=$lenS checksum=0x$([BitConverter]::ToUInt32($rawS,$chk).ToString('X8'))"
L "apexdrv: cp=$cpA cl=$clA len=$lenA checksum=0x$([BitConverter]::ToUInt32($rawA,$chk).ToString('X8'))"
L "API(full S6lan) sha1   = $([B5]::ApiSha1($S))   target=$tS1"
L "API(full S6lan) sha256 = $([B5]::ApiSha256($S))   target=$tS2"
L "API(full apexdrv) sha1 = $([B5]::ApiSha1($A))   (same as S6lan => cert region is excluded)"

# ---- what bytes differ between two files that share one API hash? ----
if ($cpS -eq $cpA -and $lenS -ge $cpS -and $lenA -ge $cpA) {
    $diffs = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt [Math]::Min($cpS, $lenA); $i++) {
        if ($rawS[$i] -ne $rawA[$i]) { $diffs.Add(("0x{0:X} {1:X2}->{2:X2}" -f $i, $rawS[$i], $rawA[$i])) }
    }
    L "pre-cert diff count = $($diffs.Count)"
    $diffs | Select-Object -First 40 | ForEach-Object { L "  diff $_" }
} else { L "cp/len mismatch: cpS=$cpS cpA=$cpA" }

$tmp = Join-Path $dir 'brute5_tmp.bin'
function Probe([string]$name, [byte[]]$buf) {
    [IO.File]::WriteAllBytes($tmp, $buf)
    $h1 = [V5]::Hx($buf, 'sha1'); $h2 = [V5]::Hx($buf, 'sha256')
    $a1 = [B5]::ApiSha1($tmp);     $a2 = [B5]::ApiSha256($tmp)
    $m1 = if ($a1 -eq $tS1) { 'API==TARGET' } elseif ($a1 -eq $h1) { 'api==plain' } else { 'api!=plain' }
    $m2 = if ($a2 -eq $tS2) { 'API==TARGET' } elseif ($a2 -eq $h2) { 'api==plain' } else { 'api!=plain' }
    L ("{0,-24} len={1,-7} sha1={2} api1={3} [{4}]" -f $name, $buf.Length, $h1, $a1, $m1)
    L ("{0,-24}          sha256={1} api2={2} [{3}]" -f '', $h2, $a2, $m2)
}
$pfx = [V5]::Slice($rawS, 0, $cpS)
Probe 'full'                $rawS
Probe 'prefix[0:cp]'        $pfx
Probe 'prefix+zerosrcdir'   ([V5]::Zero([V5]::CopyOf($pfx), $sec, 8))
Probe 'prefix+zerochecksum' ([V5]::Zero([V5]::CopyOf($pfx), $chk, 4))
Probe 'prefix+zeroboth'     ([V5]::Zero([V5]::Zero([V5]::CopyOf($pfx), $chk, 4), $sec, 8))
Probe 'apexprefix[0:cp]'    ([V5]::Slice($rawA, 0, $cpA))
Probe 'nonpe 1KB blob'      ([byte[]](0..1023 | ForEach-Object { [byte]($_ % 251) }))
L 'DONE-brute5-part2'
'sentinel-part2'
