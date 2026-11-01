Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class CE4 {
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, [MarshalAs(UnmanagedType.LPWStr)] string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminReleaseContext(IntPtr h, int flags);
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr h, byte[] pbHash, int cb, int flags, ref IntPtr prev);
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CryptCATCatalogInfoFromContext(IntPtr ci, ref CATALOG_INFO psi, int flags);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CATALOG_INFO { public int cbStruct; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string wszCatalogFile; }
    public static string FindLike(byte[] hb, string alg, bool loop) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext2(out h, ref g, alg, IntPtr.Zero, 0)) return "ctx2-ERR" + Marshal.GetLastWin32Error();
        try {
            IntPtr prev = IntPtr.Zero; var sb = new StringBuilder(); int guard = 0;
            while (true) {
                IntPtr ci = CryptCATAdminEnumCatalogFromHash(h, hb, hb.Length, 0, ref prev);
                if (ci == IntPtr.Zero) break;
                var x = new CATALOG_INFO(); x.cbStruct = Marshal.SizeOf(typeof(CATALOG_INFO));
                if (CryptCATCatalogInfoFromContext(ci, ref x, 0)) {
                    if (x.wszCatalogFile == null) sb.Append("[NULLNAME]"); else sb.Append(Path.GetFileName(x.wszCatalogFile)).Append("; ");
                } else sb.Append("?e").Append(Marshal.GetLastWin32Error()).Append("; ");
                if (!loop) break;
                if (++guard > 40) { sb.Append("[guard]"); break; }
            }
            return sb.Length > 0 ? sb.ToString().TrimEnd(' ') : "NONE(err" + Marshal.GetLastWin32Error() + ")";
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
}
'@

$d = $PSScriptRoot
$log = Join-Path $d 'probe3.txt'
"probe3 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $log
function P($s) { Add-Content -Encoding utf8 $log $s }
function Hex2Bytes($h) { $b = New-Object byte[] ($h.Length / 2); for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }; return $b }

$scan = @(Get-Content -LiteralPath (Join-Path $d 'cateng_scan.txt'))
$h1 = (($scan | Where-Object { $_ -match '^\s+sha1 engine=' } | Select-Object -Last 1) -replace '^\s+sha1 engine=', '').Trim()
$h2 = (($scan | Where-Object { $_ -match '^\s+sha256 engine=' } | Select-Object -Last 1) -replace '^\s+sha256 engine=', '').Trim()
$b1 = Hex2Bytes $h1
$b2 = Hex2Bytes $h2
P "engine tcpip sha1=$h1 sha256=$h2"

P '--- CE4 matrix (alg case x loop) on tcpip sha1'
foreach ($alg in @('SHA1', 'sha1', 'sha256')) {
    try { P ("  alg=$alg loop=true  -> " + [CE4]::FindLike($b1, $alg, $true)) } catch { P ("  alg=$alg loop=true  -> THROW " + $_.Exception.GetType().FullName + ': ' + $_.Exception.Message) }
    try { P ("  alg=$alg loop=false -> " + [CE4]::FindLike($b1, $alg, $false)) } catch { P ("  alg=$alg loop=false -> THROW " + $_.Exception.GetType().FullName + ': ' + $_.Exception.Message) }
}

P '--- dot-source real cateng.ps1 to load its CE/CE2 into this session'
$cateng = Join-Path $d 'cateng.ps1'
. $cateng -Path @() -NoApi
$asmNames = (([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetType('CE2') -or $_.GetType('CE') } | ForEach-Object { $_.GetName().Name }) -join ',')
P ('assemblies exposing CE/CE2: ' + $asmNames)

P '--- EXACT replication of cateng.ps1 line 185 semantics'
$s6 = Join-Path $d '_p25h_S6lan.sys'
$ap = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'
$bap = [CE]::DigestFileBytes($ap, 'sha1')
$bs6 = [CE]::DigestFileBytes($s6, 'sha1')
P ("apexdrv engine sha1=" + [CE]::Digest($bap, 'sha1') + "  s6len=" + (Get-Item $s6).Length + " aplen=" + (Get-Item $ap).Length + " samesha1=" + ([CE]::Digest($bap,'sha1') -eq [CE]::Digest($bs6,'sha1')))
foreach ($pair in @(@('tcpip-sha1', $b1, 'sha1'), @('tcpip-sha256', $b2, 'sha256'), @('S6lan-sha1', $bs6, 'sha1'), @('apexdrv-sha1', $bap, 'sha1'))) {
    $nm = $pair[0]; $hb = $pair[1]; $a = $pair[2]
    try {
        $r = [CE2]::FindCatalog($hb, $a)
        P ("  $nm -> " + $r)
    } catch {
        P ("  $nm -> THROW " + $_.Exception.GetType().FullName + ': ' + $_.Exception.Message)
        P ("     stack " + ($_.Exception.StackTrace -replace "`r?`n", ' | '))
    }
}
P ("component types: " + [CE4]::ToString())
'probe3-complete' | Set-Content -Encoding utf8 (Join-Path $d 'probe3_complete.txt')
