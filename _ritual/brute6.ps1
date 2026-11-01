# brute6.ps1 - BYTE-LEVEL EXCLUSION SCAN. Uses the API as oracle: for every byte of the
# pre-cert region, flip it and re-ask the API. Bytes whose flip does NOT change the API
# output ARE excluded from the catalog hash. Then reconstruct the buffer from the
# discovered exclusion set and plain-hash it: target 23C73EF9...
#   powershell -NoProfile -File _ritual\brute6.ps1
$dir = $PSScriptRoot
$out = Join-Path $dir 'brute6.txt'
$tmp = Join-Path $dir 'brute6_tmp.bin'
"brute6 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
function L($m) { Add-Content -Encoding utf8 $out $m }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
public static class B6 {
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminAcquireContext(out IntPtr h, ref Guid g, int f);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr h, IntPtr hf, ref int pcb, byte[] pb, int f);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminReleaseContext(IntPtr h, int f);
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    static string Hex(byte[] b, int n) { var s = new StringBuilder(); for (int i = 0; i < n; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }
    public static string Hx(byte[] d, string a) {
        byte[] h = (a == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d);
        return BitConverter.ToString(h).Replace("-", "");
    }
    public static string ApiSha1(string path) {
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
    static string Ranges(List<int> l) {
        var sb = new StringBuilder(); int i = 0;
        while (i < l.Count) {
            int j = i; while (j + 1 < l.Count && l[j + 1] == l[j] + 1) j++;
            if (sb.Length > 0) sb.Append(", ");
            if (i == j) sb.Append("0x" + l[i].ToString("X")); else sb.Append("0x" + l[i].ToString("X") + "-0x" + l[j].ToString("X"));
            i = j + 1;
        }
        return sb.ToString();
    }
    public static string Scan(string path, string target, string tmp) {
        byte[] raw = File.ReadAllBytes(path);
        int lf = BitConverter.ToInt32(raw, 0x3C); int opt = lf + 24;
        int chk = opt + 0x40; int sec = opt + 0x70 + 4 * 8;
        int cp = (int)BitConverter.ToUInt32(raw, sec); int cl = (int)BitConverter.ToUInt32(raw, sec + 4);
        byte[] baseBuf = new byte[cp]; Array.Copy(raw, baseBuf, cp);
        for (int i = 0; i < 8; i++) baseBuf[sec + i] = 0;   // cert dir entry -> 0 (cert-less PE)
        File.WriteAllBytes(tmp, baseBuf);
        string b0 = ApiSha1(tmp);
        var sb = new StringBuilder();
        sb.AppendLine("file=" + path + " len=" + raw.Length + " cp=" + cp + " cl=" + cl + " chk=0x" + chk.ToString("X") + " sec=0x" + sec.ToString("X"));
        sb.AppendLine("API(cert-less base)=" + b0 + "  target=" + target + "  EQUAL=" + (b0 == target));
        if (b0 != target) return sb.ToString() + "  (base does not reproduce target - scan still runs)";
        bool[] mask = new bool[cp];
        var excl = new List<int>(); var errs = new List<int>();
        for (int o = 0; o < cp; o++) {
            byte[] b = (byte[])baseBuf.Clone(); b[o] ^= 0xFF;
            File.WriteAllBytes(tmp, b);
            string h = ApiSha1(tmp);
            if (h == target) { mask[o] = true; excl.Add(o); }
            else if (h.StartsWith("ERR")) errs.Add(o);
        }
        sb.AppendLine("flip-scan: excluded=" + excl.Count + " api-err=" + errs.Count + " changed=" + (cp - excl.Count - errs.Count));
        sb.AppendLine("EXCLUDED ranges: " + Ranges(excl));
        sb.AppendLine("api-err ranges: " + Ranges(errs));

        // reconstruction from the discovered exclusion set
        byte[] mz = (byte[])baseBuf.Clone();
        for (int o = 0; o < cp; o++) if (mask[o]) mz[o] = 0;
        sb.AppendLine("model Z (zero excluded, len=" + cp + ") sha1=" + Hx(mz, "sha1") + " match=" + (Hx(mz, "sha1") == target)
                      + " sha256=" + Hx(mz, "sha256") + " match=" + (Hx(mz, "sha256") == target));
        byte[] dr = new byte[cp - excl.Count]; int j = 0;
        for (int o = 0; o < cp; o++) if (!mask[o]) dr[j++] = baseBuf[o];
        sb.AppendLine("model D (drop excluded, len=" + dr.Length + ") sha1=" + Hx(dr, "sha1") + " match=" + (Hx(dr, "sha1") == target)
                      + " sha256=" + Hx(dr, "sha256") + " match=" + (Hx(dr, "sha256") == target));
        return sb.ToString();
    }
}
'@


$S = Join-Path $dir '_p25h_S6lan.sys'
$A = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'
$t1 = '23C73EF919F18ECF9855331CF2563D3A15AF52BC'
foreach ($f in @($S, $A)) {
    L "=== scan $f"
    ([B6]::Scan($f, $t1, $tmp) -split "`r?`n") | Where-Object { $_ -ne '' } | ForEach-Object { L $_ }
    L '----'
}
L 'DONE-brute6'
Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
'brute6-complete'
