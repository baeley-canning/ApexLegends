# cateng.ps1 - PROVEN CryptCATAdminCalcHash* engine (see brute6.txt/brute7.txt) + store lookup.
#
# Transform (proven: reproduces sha1 23C73EF9... AND sha256 37647B46... exactly on two files):
#   digest stream = [0, opt+0x40) + [opt+0x44, secDir) + [secDir+8, certStart)
#   i.e. DROP OPT.Checksum (4B) and DataDirectory[4] Certificate Table entry (8B),
#   STOP at the cert table.  Plain SHA1/SHA256 over that stream.  Non-PE -> plain whole file.
#
#   -SelfTest  : engine vs CryptCATAdminCalcHashFromFileHandle2 over system drivers (both algos)
#   -Lookup    : engine hash -> CryptCATAdminEnumCatalogFromHash (end-to-end proof)
#   -ScanStores: raw scan of CatRoot/CatRoot2 for the engine hashes of the given files
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string[]]$Path,
    [ValidateSet('sha1', 'sha256')][string]$Alg = 'sha256',
    [switch]$SelfTest, [switch]$Lookup, [switch]$ScanStores, [switch]$NoApi
)
$ErrorActionPreference = 'Continue'
$dir = $PSScriptRoot
$log = Join-Path $dir 'cateng.txt'
function L($m) { Add-Content -Encoding utf8 $log $m; Write-Host $m }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
public static class CE {
    [DllImport("wintrust.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, [MarshalAs(UnmanagedType.LPWStr)] string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr hAdmin, IntPtr hFile, ref int pcb, byte[] pb, int flags);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminReleaseContext(IntPtr h, int flags);
    [DllImport("wintrust.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr hAdmin, byte[] pbHash, int cbHash, int flags, ref IntPtr prev);
    [DllImport("wintrust.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CryptCATCatalogInfoFromContext(IntPtr hInfo, ref CATALOG_INFO psi, int flags);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CATALOG_INFO { public int cbStruct; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string wszCatalogFile; }
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    static string Hex(byte[] b) { return Hex(b, b.Length); }
    static string Hex(byte[] b, int n) { var s = new StringBuilder(); for (int i = 0; i < n; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }
    static byte[] Hash(byte[] d, string a) { return (a == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d); }
    public static string Plain(byte[] d, string a) { return Hex(Hash(d, a)); }
    public static byte[] DigestBytes(byte[] raw, string a) {
        int len = raw.Length;
        if (len > 0x40 && raw[0] == 0x4D && raw[1] == 0x5A) {
            int lf = BitConverter.ToInt32(raw, 0x3C);
            if (lf > 0 && lf + 0x18 <= len && raw[lf] == 0x50 && raw[lf + 1] == 0x45 && raw[lf + 2] == 0 && raw[lf + 3] == 0) {
                int opt = lf + 24;
                int magic = BitConverter.ToUInt16(raw, opt);
                int dirOff = (magic == 0x20B) ? opt + 0x70 : (magic == 0x10B) ? opt + 0x60 : -1;
                if (dirOff > 0 && dirOff + 4 * 9 <= len) {
                    uint nDirs = BitConverter.ToUInt32(raw, dirOff - 4);
                    if (nDirs >= 5) {
                        int chk = opt + 0x40, sec = dirOff + 4 * 8;
                        int cp = (int)BitConverter.ToUInt32(raw, sec), cl = (int)BitConverter.ToUInt32(raw, sec + 4);
                        int vEnd = (cp > 0 && cl > 0 && cp <= len) ? cp : len;
                        if (chk + 4 <= sec && sec + 8 <= vEnd) {
                            var ms = new MemoryStream(vEnd);
                            ms.Write(raw, 0, chk);
                            ms.Write(raw, chk + 4, sec - (chk + 4));
                            ms.Write(raw, sec + 8, vEnd - (sec + 8));
                            return Hash(ms.ToArray(), a);
                        }
                    }
                }
            }
        }
        return Hash(raw, a);
    }
    public static string Digest(byte[] raw, string a) { return Hex(DigestBytes(raw, a)); }
    public static string DigestFile(string p, string a) { return Digest(File.ReadAllBytes(p), a); }
    public static byte[] DigestFileBytes(string p, string a) { return DigestBytes(File.ReadAllBytes(p), a); }
    public static string Api(string path, string a) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext2(out h, ref g, a.ToUpperInvariant(), IntPtr.Zero, 0))
            return "ctx2-ERR" + Marshal.GetLastWin32Error();
        try {
            using (var fs = File.OpenRead(path)) {
                byte[] buf = new byte[64]; int need = buf.Length;
                if (!CryptCATAdminCalcHashFromFileHandle2(h, fs.SafeFileHandle.DangerousGetHandle(), ref need, buf, 0))
                    return "err" + Marshal.GetLastWin32Error();
                return Hex(buf, need);
            }
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
}
'@

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class CE2 {
    [DllImport("wintrust.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, [MarshalAs(UnmanagedType.LPWStr)] string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError = true)] public static extern bool CryptCATAdminReleaseContext(IntPtr h, int flags);
    [DllImport("wintrust.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr hAdmin, byte[] pbHash, int cbHash, int flags, ref IntPtr prev);
    [DllImport("wintrust.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CryptCATCatalogInfoFromContext(IntPtr hInfo, ref CATALOG_INFO psi, int flags);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CATALOG_INFO { public int cbStruct; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string wszCatalogFile; }
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    // end-to-end: does the OS resolve OUR engine hash to a catalog?
    public static string FindCatalog(byte[] hashBytes, string a) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext2(out h, ref g, a.ToUpperInvariant(), IntPtr.Zero, 0))
            return "ctx2-ERR" + Marshal.GetLastWin32Error();
        try {
            IntPtr prev = IntPtr.Zero; var sb = new StringBuilder(); int n = 0; string last = null;
            while (true) {
                IntPtr ci = CryptCATAdminEnumCatalogFromHash(h, hashBytes, hashBytes.Length, 0, ref prev);
                if (ci == IntPtr.Zero) break;
                var x = new CATALOG_INFO(); x.cbStruct = Marshal.SizeOf(typeof(CATALOG_INFO));
                if (CryptCATCatalogInfoFromContext(ci, ref x, 0)) {
                    string nm = Path.GetFileName(x.wszCatalogFile);
                    if (nm != last) { sb.Append(nm).Append("; "); last = nm; }
                } else sb.Append("?").Append(Marshal.GetLastWin32Error()).Append("; ");
                // measured (probe4): wintrust does NOT write *phPrevCatInfo back on this build
                // (prevAfter stays NULL -> re-enum of the same catalog forever) => advance it ourselves.
                prev = ci;
                if (++n >= 64) { sb.Append("[capped]"); break; }
            }
            return sb.Length > 0 ? sb.ToString().TrimEnd(' ') : "NONE(err" + Marshal.GetLastWin32Error() + ")";
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
    public static List<string> RawScan(string root, List<string> labels, List<byte[]> pats) {
        var hits = new List<string>();
        if (!Directory.Exists(root)) return hits;
        foreach (var f in Directory.GetFiles(root, "*", SearchOption.AllDirectories)) {
            byte[] b;
            try { b = File.ReadAllBytes(f); } catch { continue; }
            for (int p = 0; p < pats.Count; p++) {
                byte[] pat = pats[p]; int off = -1, lim = b.Length - pat.Length;
                for (int i = 0; i <= lim; i++) {
                    if (b[i] != pat[0]) continue;
                    int j = 1; while (j < pat.Length && b[i + j] == pat[j]) j++;
                    if (j == pat.Length) { off = i; break; }
                }
                if (off >= 0) hits.Add(labels[p] + "  ->  " + f + " @" + off.ToString("X4") + "  filesize=" + b.Length);
            }
        }
        return hits;
    }
}
'@

# ---------------- driver ----------------
"cateng $(Get-Date -Format s)" | Set-Content -Encoding utf8 $log

if ($SelfTest) {
    $s6 = Join-Path $dir '_p25h_S6lan.sys'
    $files = @()
    foreach ($p in @($s6, (Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'), (Join-Path $env:SystemRoot 'System32\drivers\tcpip.sys'))) {
        if (Test-Path -LiteralPath $p) { $files += $p }
    }
    $files += (Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'System32\drivers') -Filter '*.sys' -ErrorAction SilentlyContinue |
               Where-Object { $_.Length -lt 3000000 } | Select-Object -First 8 -ExpandProperty FullName)
    $files += (Join-Path $env:SystemRoot 'System32\ntoskrnl.exe')
    # cert-less truncation control (proves the no-cert / vEnd=len branch)
    $raw = [IO.File]::ReadAllBytes($s6)
    $lf = [BitConverter]::ToInt32($raw, 0x3C); $sec = $lf + 24 + 0x70 + 4 * 8
    $cp = [BitConverter]::ToInt32($raw, $sec)
    $nc = New-Object byte[] $cp; [Array]::Copy($raw, $nc, $cp); 0..7 | ForEach-Object { $nc[$sec + $_] = 0 }
    $ncPath = Join-Path $dir 'cateng_nocert.bin'; [IO.File]::WriteAllBytes($ncPath, $nc); $files += $ncPath
    $ok = 0; $bad = 0
    foreach ($f in $files) {
        foreach ($a in @('sha1', 'sha256')) {
            $mine = [CE]::DigestFile($f, $a); $api = [CE]::Api($f, $a)
            $m = 'MISMATCH'; if ($mine -eq $api) { $m = 'MATCH' }
            if ($m -eq 'MATCH') { $ok++ } else { $bad++ }
            L ("{0,-30} {1,-6} {2,-8} len={3,8} engine={4} api={5}" -f (Split-Path $f -Leaf), $a, $m, (Get-Item $f).Length, $mine, $api)
        }
    }
    L "selftest: MATCH=$ok MISMATCH=$bad"
}
elseif ($Path) {
    foreach ($f in $Path) {
        if (-not (Test-Path -LiteralPath $f)) { L "MISSING $f"; continue }
        L ("=== " + $f + "  size=" + (Get-Item $f).Length)
        foreach ($a in @('sha1', 'sha256')) {
            $mine = [CE]::DigestFile($f, $a)
            $line = "  $a engine=$mine"
            if (-not $NoApi) {
                $api = [CE]::Api($f, $a)
                $line += "  api=$api  " + $(if ($mine -eq $api) { 'MATCH' } else { 'MISMATCH' })
            }
            L $line
            if ($Lookup) { L ("  $a osCatalog=" + [CE2]::FindCatalog([CE]::DigestFileBytes($f, $a), $a)) }
        }
    }
    if ($ScanStores) {
        $labels = New-Object 'System.Collections.Generic.List[string]'
        $pats = New-Object 'System.Collections.Generic.List[byte[]]'
        foreach ($f in $Path) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            foreach ($a in @('sha1', 'sha256')) {
                $labels.Add((Split-Path $f -Leaf) + '::' + $a); $pats.Add([CE]::DigestFileBytes($f, $a))
            }
        }
        foreach ($s in @("$env:SystemRoot\System32\CatRoot", "$env:SystemRoot\System32\CatRoot2")) {
            L ("--- raw scan of " + $s)
            foreach ($h in [CE2]::RawScan($s, $labels, $pats)) { L ("   " + $h) }
        }
    }
}
L 'DONE-cateng'
'cateng-complete'
