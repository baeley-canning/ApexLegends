# catlookup.ps1 - Is a file's hash covered by a catalog in the system catalog DB?
# Uses the same WinTrust CatalogAdmin API that the kernel CI path uses
# (CryptCATAdminCalcHashFromFileHandle + CryptCATAdminEnumCatalogFromHash).
# Runs NON-elevated (read-only).  Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\catlookup.ps1 <file> [<file>...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)
if (-not $Paths) { $Paths = @("$env:SystemRoot\System32\drivers\gdrv3.sys") }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class CatLookup {
    [StructLayout(LayoutKind.Sequential)]
    public struct CATALOG_INFO {
        public int cbStruct;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string wszCatalogFile;
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CryptCATAdminAcquireContext(out IntPtr phCatAdmin, ref Guid pgSubsystem, int dwFlags);
    [DllImport("wintrust.dll", SetLastError = true)]
    static extern bool CryptCATAdminCalcHashFromFileHandle(IntPtr hFile, ref int pcbHash, byte[] pbHash, int dwFlags);
    [DllImport("wintrust.dll", SetLastError = true)]
    static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr hCatAdmin, byte[] pbHash, int cbHash, int dwFlags, ref IntPtr phPrevCatInfo);
    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CryptCATCatalogInfoFromContext(IntPtr hCatInfo, ref CATALOG_INFO psCatInfo, int dwFlags);
    [DllImport("wintrust.dll")]
    static extern bool CryptCATAdminReleaseCatalogContext(IntPtr hCatAdmin, IntPtr hCatInfo, int dwFlags);
    [DllImport("wintrust.dll")]
    static extern bool CryptCATAdminReleaseContext(IntPtr hCatAdmin, int dwFlags);

    public static string Report(string path, int cbHash) {
        var sb = new StringBuilder();
        Guid g = new Guid("DE351A42-8E59-11d0-8C47-00C04FC295EE");   // "MSCAT" subsystem
        IntPtr hAdmin;
        if (!CryptCATAdminAcquireContext(out hAdmin, ref g, 0))
            return "AcquireContext FAILED err=" + Marshal.GetLastWin32Error();
        try {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                byte[] buf = new byte[cbHash];
                int cb = cbHash;
                if (!CryptCATAdminCalcHashFromFileHandle(fs.SafeFileHandle.DangerousGetHandle(), ref cb, buf, 0))
                    return "CalcHash FAILED err=" + Marshal.GetLastWin32Error();
                byte[] h = new byte[cb];
                Array.Copy(buf, h, cb);
                string algo = (cb == 32) ? "sha256" : (cb == 20 ? "sha1" : "cb" + cb);
                sb.AppendLine("  " + algo + "=" + BitConverter.ToString(h).Replace("-", ""));

                IntPtr prev = IntPtr.Zero, last = IntPtr.Zero;
                int n = 0;
                while (true) {
                    last = CryptCATAdminEnumCatalogFromHash(hAdmin, h, cb, 0, ref prev);
                    if (last == IntPtr.Zero) break;
                    var ci = new CATALOG_INFO();
                    ci.cbStruct = Marshal.SizeOf(typeof(CATALOG_INFO));
                    if (CryptCATCatalogInfoFromContext(last, ref ci, 0)) {
                        n++;
                        sb.AppendLine("  CAT[" + n + "]: " + ci.wszCatalogFile);
                    }
                    prev = last;
                }
                if (last != IntPtr.Zero) CryptCATAdminReleaseCatalogContext(hAdmin, last, 0);
                if (n == 0) sb.AppendLine("  no catalog covers this hash (" + algo + ")");
            }
        } finally { CryptCATAdminReleaseContext(hAdmin, 0); }
        return sb.ToString();
    }
}
'@

foreach ($p in $Paths) {
    Write-Output ("=== " + $p)
    if (-not (Test-Path -LiteralPath $p)) { Write-Output "  MISSING"; continue }
    foreach ($cb in @(32, 20)) { Write-Output ("-- cbHash=" + $cb); Write-Output ([CatLookup]::Report($p, $cb)) }
}
Write-Output "DONE"
