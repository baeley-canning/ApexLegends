# catdef.ps1 - DEFINITION PROVER.
# Ground truth = CryptCATAdminCalcHashFromFileHandle / ...FromFileHandle2 (what CI and
# makecat/cat member hashes actually use). Brute variants (same engine as cathash.ps1)
# are matched against that authoritative value. Whichever variant name equals the API
# hash IS the catalog-hash byte range. Read-only, non-elevated.
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\catdef.ps1 [file...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)
$dir = $PSScriptRoot
if (-not $Paths) {
    $Paths = @("$env:SystemRoot\System32\drivers\tcpip.sys",
               "$env:SystemRoot\System32\drivers\gdrv3.sys",
               "$env:SystemRoot\System32\drivers\apexdrv.sys",
               (Join-Path $dir '_p25h_S6lan.sys'))
}
$out = Join-Path $dir 'catdef.txt'
"catdef $(Get-Date -Format s)  elevated=$([bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))" |
    Set-Content -Encoding utf8 $out

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
public static class DEFCL {
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
    static string Hex(byte[] b, int n) { var s = new StringBuilder(); for (int i = 0; i < n; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    static string One(IntPtr hAdmin, IntPtr hf, bool use2) {
        byte[] buf = new byte[64]; int need = buf.Length; bool ok;
        if (use2) ok = CryptCATAdminCalcHashFromFileHandle2(hAdmin, hf, ref need, buf, 0);
        else ok = CryptCATAdminCalcHashFromFileHandle(hf, ref need, buf, 0);
        if (!ok) return "ERR" + Marshal.GetLastWin32Error();
        return Hex(buf, need);
    }
    public static string Api(string path) {
        var sb = new StringBuilder();
        using (FileStream fs = File.OpenRead(path)) {
            IntPtr hf = fs.SafeFileHandle.DangerousGetHandle();
            sb.AppendLine("  api.calcHash        = " + One(IntPtr.Zero, hf, false) + "   (default class)");
            Guid sub = DRV; IntPtr h = IntPtr.Zero;
            if (CryptCATAdminAcquireContext2(out h, ref sub, "SHA256", IntPtr.Zero, 0)) {
                sb.AppendLine("  api.calcHash2/sha256 = " + One(h, hf, true));
                CryptCATAdminReleaseContext(h, 0);
            } else sb.AppendLine("  api.calcHash2/sha256 = ctx2 fail err=" + Marshal.GetLastWin32Error());
            IntPtr h1 = IntPtr.Zero;
            if (CryptCATAdminAcquireContext(out h1, ref sub, 0)) {
                sb.AppendLine("  api.calcHash2/sha1   = " + One(h1, hf, true));
                CryptCATAdminReleaseContext(h1, 0);
            } else sb.AppendLine("  api.calcHash2/sha1   = ctxL fail err=" + Marshal.GetLastWin32Error());
        }
        return sb.ToString();
    }
}
'@

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
public static class VH {
    public static string Hx(byte[] d, string algo) {
        byte[] h = (algo == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d);
        return BitConverter.ToString(h).Replace("-", "");
    }
    static readonly string[] MODES = { "full", "tocp", "cp8dn", "cp8up", "zerocert" };
    public static List<string> Variants(string path, List<string> names) {
        var vals = new List<string>();
        byte[] raw;
        try { raw = File.ReadAllBytes(path); } catch { return vals; }
        if (raw.Length < 0x40) return vals;
        int lf = BitConverter.ToInt32(raw, 0x3C);
        if (lf <= 0 || lf + 0x60 > raw.Length || raw[lf] != 0x50 || raw[lf + 1] != 0x45) return vals;
        int opt = lf + 24;
        bool p32p = BitConverter.ToUInt16(raw, opt) == 0x20B;
        int dirOff = opt + (p32p ? 0x70 : 0x60);
        int se = dirOff + 32;
        if (se + 8 > raw.Length) return vals;
        long cl = BitConverter.ToUInt32(raw, se + 4);
        long cp = BitConverter.ToUInt32(raw, se);
        int cpI = (cp > 0 && cp < raw.Length) ? (int)cp : raw.Length;
        int cp8dn = cpI & ~7;
        int cp8up = (cpI + 7) & ~7; if (cp8up > raw.Length) cp8up = raw.Length;
        names.Add("(-- cert off=" + cp + " len=" + cl + " filelen=" + raw.Length + " --)");
        vals.Add("");
        for (int zc = 0; zc < 2; zc++)
        for (int zs = 0; zs < 2; zs++)
        for (int m = 0; m < MODES.Length; m++) {
            byte[] b = (byte[])raw.Clone();
            if (zc == 1) for (int i = 0; i < 4; i++) b[opt + 0x40 + i] = 0;
            if (zs == 1) for (int i = 0; i < 8; i++) b[se + i] = 0;
            int n;
            switch (MODES[m]) {
                case "tocp":  n = cpI;   break;
                case "cp8dn": n = cp8dn; break;
                case "cp8up": n = cp8up; break;
                default:      n = b.Length; break;
            }
            if (MODES[m] == "zerocert" && cl > 0 && cpI + cl <= b.Length)
                for (int i = cpI; i < cpI + cl; i++) b[i] = 0;
            if (n < 0 || n > b.Length) n = b.Length;
            byte[] r = new byte[n]; Array.Copy(b, r, n);
            string nm = "ck" + zc + "_sec" + zs + "_" + MODES[m];
            names.Add(nm + ".sha1");   vals.Add(Hx(r, "sha1"));
            names.Add(nm + ".sha256"); vals.Add(Hx(r, "sha256"));
        }
        return vals;
    }
}
'@

foreach ($p in $Paths) {
    Add-Content -Encoding utf8 $out ("=== " + $p)
    if (-not (Test-Path -LiteralPath $p)) { Add-Content -Encoding utf8 $out '  MISSING'; continue }
    $api = [DEFCL]::Api($p)
    Add-Content -Encoding utf8 $out $api
    $names = New-Object 'System.Collections.Generic.List[string]'
    $vals  = [VH]::Variants($p, $names)
    if ($vals.Count -eq 0) { Add-Content -Encoding utf8 $out '  not a parseable PE'; continue }
    $apiVals = @()
    foreach ($m in [regex]::Matches($api, '=\s*([0-9A-F]{20,64})')) { $apiVals += $m.Groups[1].Value }
    $matchCount = 0
    for ($i = 0; $i -lt $names.Count; $i++) {
        if (-not $names[$i]) { continue }
        $mark = if ($apiVals -contains $vals[$i]) { $matchCount++; 'MATCH' } else { '     ' }
        Add-Content -Encoding utf8 $out ("  {0} {1} {2}" -f $mark, $names[$i].PadRight(24), $vals[$i])
    }
    Add-Content -Encoding utf8 $out ("  >>> api-hash reproduced by {0} variant(s)" -f $matchCount)
}
Add-Content -Encoding utf8 $out 'DONE'
'WROTE catdef.txt'
