# catlookup2.ps1 - GROUND TRUTH: ask WinTrust itself whether a catalog covers a file.
# Legacy codepath needs NO admin: CryptCATAdminCalcHashFromFileHandle +
# CryptCATAdminEnumCatalogFromHash(NULL, hash, ...) (NULL admin => slow but valid search).
# Also tries AcquireContext2 (Win8+) and the hCatAdmin-based enum, and for each catalog
# found reports its signature status + /kp verdict. Read-only.
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\catlookup2.ps1 [file...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)
if (-not $Paths) {
    $Paths = @("$env:SystemRoot\System32\drivers\gdrv3.sys",
               "$env:SystemRoot\System32\drivers\tcpip.sys",
               "$env:SystemRoot\System32\drivers\apexdrv.sys",
               "$env:SystemRoot\System32\ntoskrnl.exe")
}

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class CL {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CATALOG_INFO { public int cbStruct; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string wszCatalogFile; }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminAcquireContext(out IntPtr h, ref Guid sub, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminCalcHashFromFileHandle(IntPtr hFile, ref int pcb, byte[] pb, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr hAdmin, byte[] pbHash, int cb, int flags, ref IntPtr prev);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATCatalogInfoFromContext(IntPtr hCat, ref CATALOG_INFO info, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminReleaseCatalogContext(IntPtr hAdmin, IntPtr hCat, int flags);
    [DllImport("wintrust.dll", SetLastError = true)]
    public static extern bool CryptCATAdminReleaseContext(IntPtr hAdmin, int flags);

    static string Hex(byte[] b, int n) { var s = new StringBuilder(); for (int i = 0; i < n; i++) s.Append(b[i].ToString("X2")); return s.ToString(); }

    public static int IndexOf(byte[] hay, byte[] pat) {
        int lim = hay.Length - pat.Length;
        for (int i = 0; i <= lim; i++) {
            if (hay[i] != pat[0]) continue;
            int j = 1; while (j < pat.Length && hay[i + j] == pat[j]) j++;
            if (j == pat.Length) return i;
        }
        return -1;
    }

    // Independent membership test: crack open the driver cat store and look for the
    // 20-byte flat hash as raw bytes or as ASCII hex (that is how members are stored).
    public static string ScanStore(byte[] hash) {
        var sb = new StringBuilder();
        string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string[] dirs = new string[] {
            Path.Combine(win, "System32", "CatRoot",  "{F750E6C3-38EE-11D1-85E5-00C04FC295EE}"),
            Path.Combine(win, "System32", "CatRoot2", "{F750E6C3-38EE-11D1-85E5-00C04FC295EE}")
        };
        string hexU = Hex(hash, hash.Length);
        byte[] aU = Encoding.ASCII.GetBytes(hexU);
        byte[] aL = Encoding.ASCII.GetBytes(hexU.ToLowerInvariant());
        int nf = 0, nh = 0;
        foreach (string d in dirs) {
            if (!Directory.Exists(d)) { sb.AppendLine("    rawscan MISSING " + d); continue; }
            string[] fs;
            try { fs = Directory.GetFiles(d, "*", SearchOption.AllDirectories); } catch { continue; }
            foreach (string f in fs) {
                nf++;
                byte[] b; try { b = File.ReadAllBytes(f); } catch { continue; }
                bool h1 = IndexOf(b, hash) >= 0, h2 = IndexOf(b, aU) >= 0, h3 = IndexOf(b, aL) >= 0;
                if (h1 || h2 || h3) { nh++; sb.AppendLine("    RAWHIT[" + (h1 ? " bin" : "") + (h2 ? " hexU" : "") + (h3 ? " hexL" : "") + "] " + f); }
            }
        }
        sb.AppendLine("    rawscan files=" + nf + " hits=" + nh);
        return sb.ToString();
    }

    public static string EnumOne(IntPtr hAdmin, byte[] hash, int cb, string tag) {
        var sb = new StringBuilder();
        IntPtr prev = IntPtr.Zero; int n = 0;
        while (true) {
            IntPtr hCat = CryptCATAdminEnumCatalogFromHash(hAdmin, hash, cb, 0, ref prev);
            if (hCat == IntPtr.Zero) break;
            var ci = new CATALOG_INFO(); ci.cbStruct = Marshal.SizeOf(typeof(CATALOG_INFO));
            if (CryptCATCatalogInfoFromContext(hCat, ref ci, 0)) { sb.AppendLine("    " + tag + " CATALOG: " + ci.wszCatalogFile); n++; }
            else sb.AppendLine("    " + tag + " ctx found, info failed err=" + Marshal.GetLastWin32Error());
            CryptCATAdminReleaseCatalogContext(hAdmin, hCat, 0);
            prev = hCat;
            if (n > 12) break;
        }
        if (n == 0) sb.AppendLine("    " + tag + " -> no catalog (lastErr=" + Marshal.GetLastWin32Error() + ")");
        return sb.ToString();
    }

    public static string Do(string path) {
        var sb = new StringBuilder();
        // DRIVER_ACTION_VERIFY is the driver cat store that actually exists in CatRoot;
        // WINDOWS_ACTION_VERIFY only exists once something creates it (create == ACCESS_DENIED
        // for a non-admin), which is why the old code got err=5 and a NULL context.
        Guid[] subs = new Guid[] {
            new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE"),
            new Guid("DE351A42-8E59-11D0-8C47-00C04FC295EE")
        };
        byte[] hash = null;
        using (FileStream fs = File.OpenRead(path)) {
            IntPtr hf = fs.SafeFileHandle.DangerousGetHandle();
            byte[] buf = new byte[32]; int need = buf.Length;
            bool ok = CryptCATAdminCalcHashFromFileHandle(hf, ref need, buf, 0);
            sb.AppendLine("  CalcHash=" + ok + (ok ? " hash=" + Hex(buf, need) : " err=" + Marshal.GetLastWin32Error()));
            if (ok) { hash = new byte[need]; Array.Copy(buf, hash, need); }
        }
        if (hash == null) return sb.ToString();
        sb.Append(ScanStore(hash));
        foreach (Guid sub0 in subs) { Guid sub = sub0;
            string g8 = sub.ToString().Substring(0, 8);
            IntPtr h2 = IntPtr.Zero, hl = IntPtr.Zero;
            bool g2 = CryptCATAdminAcquireContext2(out h2, ref sub, "SHA256", IntPtr.Zero, 0);
            sb.AppendLine("  ctx2[" + g8 + "]=" + g2 + (g2 ? "" : " err=" + Marshal.GetLastWin32Error()));
            bool gl = CryptCATAdminAcquireContext(out hl, ref sub, 0);
            sb.AppendLine("  ctxL[" + g8 + "]=" + gl + (gl ? "" : " err=" + Marshal.GetLastWin32Error()));
            if (g2) sb.Append(EnumOne(h2, hash, hash.Length, "ctx2[" + g8 + "]"));
            if (gl) sb.Append(EnumOne(hl, hash, hash.Length, "ctxL[" + g8 + "]"));
            sb.Append(EnumOne(IntPtr.Zero, hash, hash.Length, "NULL[" + g8 + "]"));
            if (g2) CryptCATAdminReleaseContext(h2, 0);
            if (gl) CryptCATAdminReleaseContext(hl, 0);
        }
        return sb.ToString();
    }
}
'@
$sig = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

Write-Output ("elevated=" + [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
foreach ($p in $Paths) {
    Write-Output ("=== " + $p)
    if (-not (Test-Path -LiteralPath $p)) { Write-Output '  MISSING'; continue }
    $fi = Get-Item -LiteralPath $p
    Write-Output ("  size=" + $fi.Length + "  mtime=" + $fi.LastWriteTime)
    $out = ''
    try { $out = [CL]::Do($p); Write-Output $out } catch { Write-Output ("  API THREW: " + $_.Exception.Message) }
    $st = Get-AuthenticodeSignature -LiteralPath $p
    Write-Output ("  AuthSig: status=" + $st.Status + " type=" + $st.SignatureType + " signer=" + $st.SignerCertificate.Subject)
    if ($st.SignerCertificate) {
        $chf = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chf.ChainPolicy.RevocationMode = 'NoCheck'
        [void]$chf.Build($st.SignerCertificate)
        Write-Output ("  fileChainRoot: " + $chf.ChainElements[$chf.ChainElements.Count - 1].Certificate.Subject)
    }
    $cats = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($out, 'CATALOG:\s*(.+?)\s*$')) { if (-not $cats.Contains($m.Groups[1].Value)) { $cats.Add($m.Groups[1].Value) } }
    if ($st.SignatureType -eq 'Catalog' -and $st.Path -and -not $cats.Contains($st.Path)) { $cats.Add($st.Path) }
    foreach ($cat in $cats) {
        Write-Output ("  >>> CATALOG FOUND: " + $cat)
        if (-not (Test-Path -LiteralPath $cat)) { Write-Output '      (gone)'; continue }
        $cs = Get-AuthenticodeSignature -LiteralPath $cat
        Write-Output ("      catAuthSig: status=" + $cs.Status + " signer=" + $cs.SignerCertificate.Subject)
        if ($cs.SignerCertificate) {
            $chc = New-Object System.Security.Cryptography.X509Certificates.X509Chain
            $chc.ChainPolicy.RevocationMode = 'NoCheck'
            [void]$chc.Build($cs.SignerCertificate)
            Write-Output ("      catChainRoot: " + $chc.ChainElements[$chc.ChainElements.Count - 1].Certificate.Subject)
        }
        foreach ($md in @('/kp', '/pa')) {
            $sv = ((& $sig verify /v $md $cat 2>&1) -join "`n")
            foreach ($ln in ($sv -split "`n" | Where-Object { $_ -match 'Issued to|does not chain|SignTool Error|Number of errors' })) { Write-Output ("      CAT" + $md.Trim('/').ToUpper() + " " + $ln.Trim()) }
        }
    }
}
Write-Output 'DONE'
