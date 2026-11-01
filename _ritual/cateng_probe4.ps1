Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Diagnostics;
public static class CE5 {
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, [MarshalAs(UnmanagedType.LPWStr)] string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminReleaseContext(IntPtr h, int flags);
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr h, byte[] pbHash, int cb, int flags, ref IntPtr prev);
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CryptCATCatalogInfoFromContext(IntPtr ci, ref CATALOG_INFO pi, int flags);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CATALOG_INFO { public int cbStruct; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string wszCatalogFile; }
    static string Hex(byte[] b) { var s = new StringBuilder(); for (int i = 0; i < b.Length; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }
    static byte[] Hash(byte[] d, string a) { return (a == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d); }
    public static byte[] DigestBytes(byte[] raw, string a) {
        int len = raw.Length;
        if (len > 0x40 && raw[0] == 0x4D && raw[1] == 0x5A) {
            int lf = BitConverter.ToInt32(raw, 0x3C);
            if (lf > 0 && lf + 0x18 <= len && raw[lf] == 0x50 && raw[lf+1] == 0x45 && raw[lf+2] == 0 && raw[lf+3] == 0) {
                int opt = lf + 24, magic = BitConverter.ToUInt16(raw, opt);
                int dirOff = (magic == 0x20B) ? opt + 0x70 : (magic == 0x10B) ? opt + 0x60 : -1;
                if (dirOff > 0 && dirOff + 4 * 9 <= len) {
                    uint nDirs = BitConverter.ToUInt32(raw, dirOff - 4);
                    if (nDirs >= 5) {
                        int chk = opt + 0x40, sec = dirOff + 4 * 8;
                        int cp = (int)BitConverter.ToUInt32(raw, sec), cl = (int)BitConverter.ToUInt32(raw, sec + 4);
                        int vEnd = (cp > 0 && cl > 0 && cp <= len) ? cp : len;
                        if (chk + 4 <= sec && sec + 8 <= vEnd) {
                            var ms = new MemoryStream(vEnd);
                            ms.Write(raw, 0, chk); ms.Write(raw, chk + 4, sec - (chk + 4)); ms.Write(raw, sec + 8, vEnd - (sec + 8));
                            return Hash(ms.ToArray(), a);
                        }
                    }
                }
            }
        }
        return Hash(raw, a);
    }
    public static string DigestFile(string p, string a) { return Hex(DigestBytes(File.ReadAllBytes(p), a)); }
    static string Name(IntPtr ci, out int err) {
        err = 0; var x = new CATALOG_INFO(); x.cbStruct = Marshal.SizeOf(typeof(CATALOG_INFO));
        if (!CryptCATCatalogInfoFromContext(ci, ref x, 0)) { err = Marshal.GetLastWin32Error(); return "?_infoErr"; }
        return x.wszCatalogFile == null ? "?_NULLNAME" : Path.GetFileName(x.wszCatalogFile);
    }
    public static string DiagWriteback(byte[] hb, string alg, int cap, out int calls, out long ms) {
        var sw = Stopwatch.StartNew(); IntPtr h; Guid g = DRV; calls = 0; ms = 0;
        if (!CryptCATAdminAcquireContext2(out h, ref g, alg, IntPtr.Zero, 0)) { ms = sw.ElapsedMilliseconds; return "ctx-ERR" + Marshal.GetLastWin32Error(); }
        try {
            IntPtr prev = IntPtr.Zero; string first = null; int err = 0;
            while (true) {
                IntPtr ci = CryptCATAdminEnumCatalogFromHash(h, hb, hb.Length, 0, ref prev);
                if (ci == IntPtr.Zero) { err = Marshal.GetLastWin32Error(); break; }
                calls++; if (first == null) first = Name(ci, out err);
                if (calls > cap) break;
            }
            ms = sw.ElapsedMilliseconds;
            return first == null ? "NONE(err" + err + ")" : first;
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
    public static string DiagExplicit(byte[] hb, string alg, int cap, out int calls, out long ms) {
        var sw = Stopwatch.StartNew(); IntPtr h; Guid g = DRV; calls = 0; ms = 0;
        if (!CryptCATAdminAcquireContext2(out h, ref g, alg, IntPtr.Zero, 0)) { ms = sw.ElapsedMilliseconds; return "ctx-ERR" + Marshal.GetLastWin32Error(); }
        try {
            IntPtr prev = IntPtr.Zero; string first = null; int err = 0;
            while (true) {
                IntPtr ci = CryptCATAdminEnumCatalogFromHash(h, hb, hb.Length, 0, ref prev);
                if (ci == IntPtr.Zero) { err = Marshal.GetLastWin32Error(); break; }
                calls++; if (first == null) first = Name(ci, out err);
                prev = ci;
                if (calls > cap) break;
            }
            ms = sw.ElapsedMilliseconds;
            return first == null ? "NONE(err" + err + ")" : first;
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
    public static string DiagOnce(byte[] hb, string alg, out long ms) {
        var sw = Stopwatch.StartNew(); IntPtr h; Guid g = DRV; ms = 0;
        if (!CryptCATAdminAcquireContext2(out h, ref g, alg, IntPtr.Zero, 0)) { ms = sw.ElapsedMilliseconds; return "ctx-ERR" + Marshal.GetLastWin32Error(); }
        try {
            IntPtr prev = IntPtr.Zero;
            IntPtr ci = CryptCATAdminEnumCatalogFromHash(h, hb, hb.Length, 0, ref prev);
            ms = sw.ElapsedMilliseconds;
            if (ci == IntPtr.Zero) return "NONE(err" + Marshal.GetLastWin32Error() + ")";
            int err; string nm = Name(ci, out err);
            return nm + " [prevAfter=" + (prev == IntPtr.Zero ? "NULL" : "SET") + "]";
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
}
'@

$d = $PSScriptRoot
$log = Join-Path $d 'probe4.txt'
"probe4 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $log
function P($s) { Add-Content -Encoding utf8 $log $s }

$tcp = Join-Path $env:SystemRoot 'System32\drivers\tcpip.sys'
$s6 = Join-Path $d '_p25h_S6lan.sys'
$ap = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'
$bt = [CE5]::DigestBytes([IO.File]::ReadAllBytes($tcp), 'sha1')
$ba = [CE5]::DigestBytes([IO.File]::ReadAllBytes($ap), 'sha1')
$bs = [CE5]::DigestBytes([IO.File]::ReadAllBytes($s6), 'sha1')
P ("tcpip  sha1=" + [CE5]::DigestFile($tcp, 'sha1'))
P ("apexdrv sha1=" + [CE5]::DigestFile($ap, 'sha1'))
P ("S6lan  sha1=" + [CE5]::DigestFile($s6, 'sha1') + "  sameAsApex=" + ((Compare-Object $ba $bs) -eq $null))

foreach ($c in @(@('tcpip', $bt, 'SHA1'), @('apexdrv', $ba, 'SHA1'))) {
    $n = 0; $ms = 0
    $r = [CE5]::DiagWriteback($c[1], $c[2], 500, [ref]$n, [ref]$ms)
    P ("  {0} writeback calls={1} ms={2} -> {3}" -f $c[0], $n, $ms, $r)
    $n = 0; $ms = 0
    $r = [CE5]::DiagExplicit($c[1], $c[2], 500, [ref]$n, [ref]$ms)
    P ("  {0} explicit  calls={1} ms={2} -> {3}" -f $c[0], $n, $ms, $r)
    $ms = 0
    $r = [CE5]::DiagOnce($c[1], $c[2], [ref]$ms)
    P ("  {0} once      ms={1} -> {2}" -f $c[0], $ms, $r)
}

$code = ". '" + (Join-Path $d 'cateng.ps1') + "' -Path @(); [CE2]::FindCatalog([CE]::DigestFileBytes('" + $tcp + "','sha1'),'sha1')"
$out = Join-Path $d 'probe4_child.out'
$errf = Join-Path $d 'probe4_child.err'
Remove-Item -LiteralPath $out, $errf -ErrorAction SilentlyContinue
$psi = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $code -PassThru -RedirectStandardOutput $out -RedirectStandardError $errf -WindowStyle Hidden
$hung = -not $psi.WaitForExit(25000)
if ($hung) { P 'CHILD real CE2.FindCatalog: STILL RUNNING after 25s -> HANG'; $psi.Kill() }
else { P ('CHILD real CE2.FindCatalog: exited 0x{0:X}' -f $psi.ExitCode) }
Start-Sleep -Milliseconds 500
if (Test-Path $out) { $c = Get-Content -LiteralPath $out -Raw; P ("CHILD stdout len=" + $c.Length + " head=" + $c.Substring(0, [Math]::Min(200, $c.Length))) }
if (Test-Path $errf) { $e = Get-Content -LiteralPath $errf -Raw; if ($e) { P ("CHILD stderr=" + $e.Substring(0, [Math]::Min(400, $e.Length))) } }
'probe4-complete' | Set-Content -Encoding utf8 (Join-Path $d 'probe4_complete.txt')
