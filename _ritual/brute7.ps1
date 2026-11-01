# brute7.ps1 - confirm the exact transform by enumerating keep/zero/drop for the three
# regions the API ignores: OPT.Checksum(4), OPT.CertTable dir entry(8), cert region.
# Winner must reproduce BOTH recorded targets (sha1 23C73EF9... / sha256 37647B46...)
# AND be a fixed point of the API on itself.
$dir = $PSScriptRoot
$out = Join-Path $dir 'brute7.txt'
$tmp = Join-Path $dir 'brute7_tmp.bin'
"brute7 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
function L($m) { Add-Content -Encoding utf8 $out $m }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
public static class B7 {
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminAcquireContext(out IntPtr h, ref Guid g, int f);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr h, IntPtr hf, ref int pcb, byte[] pb, int f);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminReleaseContext(IntPtr h, int f);
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    static string Hex(byte[] b, int n) { var s = new StringBuilder(); for (int i = 0; i < n; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }
    public static string Hx(byte[] d, string a) {
        byte[] h = (a == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d);
        return BitConverter.ToString(h).Replace("-", "");
    }
    public static string Api(string path, string algo, bool sha256) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext(out h, ref g, 0)) return "ctxL-ERR" + Marshal.GetLastWin32Error();
        try {
            using (var fs = File.OpenRead(path)) {
                byte[] buf = new byte[64]; int need = buf.Length;
                if (!CryptCATAdminCalcHashFromFileHandle2(h, fs.SafeFileHandle.DangerousGetHandle(), ref need, buf, 0))
                    return "ERR" + Marshal.GetLastWin32Error();
                return Hex(buf, need);
            }
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
    // op: 0=keep, 1=zero, 2=drop
    public static byte[] Build(byte[] raw, int cp, int cl, int chk, int sec, int opChk, int opSm, int opCert) {
        bool[] skip = new bool[cp];
        if (opChk == 2) for (int i = 0; i < 4; i++) skip[chk + i] = true;
        if (opSm == 2) for (int i = 0; i < 8; i++) skip[sec + i] = true;
        var ms = new MemoryStream();
        for (int i = 0; i < cp; i++) {
            if (skip[i]) continue;
            byte v = raw[i];
            if (opChk == 1 && i >= chk && i < chk + 4) v = 0;
            if (opSm == 1 && i >= sec && i < sec + 8) v = 0;
            ms.WriteByte(v);
        }
        int total = cp - (opChk == 2 ? 4 : 0) - (opSm == 2 ? 8 : 0);
        int cn = (opCert == 2) ? 0 : cl;
        if (opCert == 1) for (int i = 0; i < cn; i++) ms.WriteByte(0);
        else if (opCert == 0) { for (int i = 0; i < cn; i++) ms.WriteByte(raw[cp + i]); }
        return ms.ToArray();
    }
    public static string Run(string path, string t1, string t2) {
        byte[] raw = File.ReadAllBytes(path);
        int lf = BitConverter.ToInt32(raw, 0x3C); int opt = lf + 24;
        int chk = opt + 0x40; int sec = opt + 0x70 + 4 * 8;
        int cp = (int)BitConverter.ToUInt32(raw, sec); int cl = (int)BitConverter.ToUInt32(raw, sec + 4);
        var sb = new StringBuilder();
        sb.AppendLine("file=" + path + " cp=" + cp + " cl=" + cl + " len=" + raw.Length);
        sb.AppendLine("API(full) sha1=" + Api(path, "sha1", false) + " sha256=" + Api(path, "sha256", true));
        foreach (int a in new int[] { 0, 1, 2 }) foreach (int b in new int[] { 0, 1, 2 }) foreach (int c in new int[] { 0, 1, 2 }) {
            byte[] buf = Build(raw, cp, cl, chk, sec, a, b, c);
            File.WriteAllBytes(tmpPath, buf);
            string h1 = Hx(buf, "sha1"), h2 = Hx(buf, "sha256");
            bool m1 = h1 == t1, m2 = h2 == t2;
            if (m1 || m2)
                sb.AppendLine("  HIT chkOp=" + a + " secOp=" + b + " certOp=" + c + " len=" + buf.Length + " sha1match=" + m1 + " sha256match=" + m2
                              + " api1=" + Api(tmpPath, "sha1", false) + " api2=" + Api(tmpPath, "sha256", true));
        }
        return sb.ToString();
    }
    public static string tmpPath;
}
'@

$S = Join-Path $dir '_p25h_S6lan.sys'
$A = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'
$t1 = '23C73EF919F18ECF9855331CF2563D3A15AF52BC'
$t2 = '37647B4654AE7F7608D8012A4BAA5AA8FB843552F6F053C2549ECE167D4C6EE8'
[B7]::tmpPath = $tmp
foreach ($f in @($S, $A)) {
    L "=== $f"
    ([B7]::Run($f, $t1, $t2) -split "`r?`n") | Where-Object { $_ -ne '' } | ForEach-Object { L $_ }
}
L 'DONE-brute7'
'brute7-complete'
