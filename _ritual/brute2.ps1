# brute2.ps1 - reverse-engineer the TRUE api hash range/zeroing from ground truth.
# For a small file: exhaustive n = 0..len with several zeroing combos; for a large
# file: candidate n around cert offset / lengths only. Prints every hit.
#   powershell -NoProfile -File _ritual\brute2.ps1
$dir = $PSScriptRoot
$out = Join-Path $dir 'brute2.txt'
$targets = @{
    (Join-Path $dir '_p25h_S6lan.sys')           = '37647B4654AE7F7608D8012A4BAA5AA8FB843552F6F053C2549ECE167D4C6EE8'
    "$env:SystemRoot\System32\drivers\tcpip.sys" = '91277E39C4F76D6D0F296657AFE1702297CBC92051F38CCF2F72D3BD5A39997F'
    "$env:SystemRoot\System32\drivers\gdrv3.sys" = 'PLACEHOLDER_GDRV3'
    "$env:SystemRoot\System32\drivers\apexdrv.sys" = 'PLACEHOLDER_APEX'
}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
public static class B2 {
    static string Hx(byte[] b) { return BitConverter.ToString(SHA256.Create().ComputeHash(b)).Replace("-",""); }
    [DllImport("wintrust.dll", SetLastError = true)] static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid g, string alg, IntPtr pol, int f);
    [DllImport("wintrust.dll", SetLastError = true)] static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr h, IntPtr hf, ref int pcb, byte[] pb, int f);
    public static string ApiSha256(string path) {
        Guid g = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE"); IntPtr h;
        if (!CryptCATAdminAcquireContext2(out h, ref g, "SHA256", IntPtr.Zero, 0)) return "CTXFAIL";
        using (var fs = File.OpenRead(path)) {
            byte[] buf = new byte[64]; int need = 0;
            if (!CryptCATAdminCalcHashFromFileHandle2(h, fs.SafeFileHandle.DangerousGetHandle(), ref need, buf, 0)) return "ERR" + Marshal.GetLastWin32Error();
            return BitConverter.ToString(buf, 0, need).Replace("-", "");
        }
    }
    public static string Parse(string p, out int cp, out int cl, out int se, out int chek, out int len) {
        cp = cl = se = chek = len = 0;
        byte[] raw = File.ReadAllBytes(p); len = raw.Length;
        int lf = BitConverter.ToInt32(raw, 0x3C);
        if (raw[lf] != 0x50 || raw[lf+1] != 0x45) return "notpe";
        int opt = lf + 24; bool p32p = BitConverter.ToUInt16(raw, opt) == 0x20B;
        int dirOff = opt + (p32p ? 0x70 : 0x60);
        se = dirOff + 32; chek = opt + 0x40;
        cl = (int)BitConverter.ToUInt32(raw, se + 4);
        cp = (int)BitConverter.ToUInt32(raw, se);
        return "ok";
    }
    public static string Run(string p, string target, int[] ns) {
        var sb = new StringBuilder();
        byte[] raw = File.ReadAllBytes(p);
        int lf = BitConverter.ToInt32(raw, 0x3C);
        int opt = lf + 24; bool p32p = BitConverter.ToUInt16(raw, opt) == 0x20B;
        int dirOff = opt + (p32p ? 0x70 : 0x60);
        int se = dirOff + 32; int chek = opt + 0x40;
        int cp = (int)BitConverter.ToUInt32(raw, se); int cl = (int)BitConverter.ToUInt32(raw, se + 4);
        string[] combos = { "plain", "zc", "zs", "zc+zs" };
        foreach (int n in ns) {
            if (n < 0 || n > raw.Length) continue;
            foreach (string c in combos) {
                byte[] b = (byte[])raw.Clone();
                if (c.Contains("zc")) for (int i = 0; i < 4; i++) b[chek + i] = 0;
                if (c.Contains("zs")) for (int i = 0; i < 8; i++) b[se + i] = 0;
                byte[] r = new byte[n]; Array.Copy(b, r, n);
                string h = Hx(r);
                if (h == target) sb.AppendLine("  HIT n=" + n + " combo=" + c + "  ->  " + h);
            }
        }
        if (sb.Length == 0) sb.AppendLine("  no hit  (cp=" + cp + " cl=" + cl + " len=" + raw.Length + ")");
        return sb.ToString();
    }
}
'@
"brute2 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
foreach ($p in $targets.Keys) {
    $t = $targets[$p]
    if ($t -like 'PLACEHOLDER*') { $t = [B2]::ApiSha256($p) }
    Add-Content -Encoding utf8 $out ("=== " + $p + "  target=" + $t)
    if (-not (Test-Path -LiteralPath $p)) { Add-Content -Encoding utf8 $out '  MISSING'; continue }
    $len = (Get-Item -LiteralPath $p).Length
    $cp = 0; $cl = 0; $se = 0; $chk = 0; $l = 0
    $st = [B2]::Parse($p, [ref]$cp, [ref]$cl, [ref]$se, [ref]$chk, [ref]$l)
    Add-Content -Encoding utf8 $out ("  parse=" + $st + " cp=" + $cp + " cl=" + $cl + " len=" + $l + " secOff=" + $se + " chkOff=" + $chk)
    $ns = New-Object 'System.Collections.Generic.List[int]'
    if ($len -le 200000) {
        for ($n = 0; $n -le $len; $n++) { $ns.Add($n) }
    } else {
        $c = @(0, 0x40, $cp - 0x100, $cp - 0x80, $cp - 8, $cp, $cp + 8, ($cp -band -bnot 7), (($cp + 7) -band -bnot 7), $cp + $cl, $len)
        foreach ($v in $c) { for ($d = -8; $d -le 8; $d++) { $ns.Add($v + $d) } }
    }
    Add-Content -Encoding utf8 $out ([B2]::Run($p, $t, $ns.ToArray()))
}
Add-Content -Encoding utf8 $out 'DONE'
'wrote brute2.txt'
