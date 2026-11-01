# catfind2.ps1 - which installed catalog (if any) covers a file?
# Uses the Authenticode FLAT hash (PE checksum + security-directory zeroed, cert table
# excluded) that CryptCATAdminCalcHashFromFileHandle computes and catalogs store.
# Raw Get-FileHash (whole file incl. signature) is printed too, for contrast.
# Read-only, non-elevated.
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\catfind2.ps1 <file> [<file>...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)
if (-not $Paths) {
    $Paths = @("$env:SystemRoot\System32\drivers\gdrv3.sys",
               "$env:SystemRoot\System32\drivers\tcpip.sys")
}

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;

public static class CatHash {
    public static bool IsAdmin() {
        var p = new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent());
        return p.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    }

    // flat blob = file bytes with PE checksum + cert data-directory zeroed, cert table cut off
    public static bool Flat(string path, out byte[] outp) {
        outp = null;
        byte[] b;
        try { b = File.ReadAllBytes(path); } catch { return false; }
        if (b.Length < 0x40) return false;
        int lfanew = BitConverter.ToInt32(b, 0x3C);
        if (lfanew <= 0 || lfanew + 0x60 > b.Length) return false;
        if (b[lfanew] != 0x50 || b[lfanew + 1] != 0x45) return false;   // "PE"
        int opt = lfanew + 24;
        if (opt + 0x70 > b.Length) return false;
        bool pe32p = BitConverter.ToUInt16(b, opt) == 0x20B;
        int dirOff = opt + (pe32p ? 0x70 : 0x60);
        int secEnt = dirOff + 4 * 8;                 // data dir [4] = Certificate Table
        if (secEnt + 8 > b.Length) return false;
        for (int i = 0; i < 4; i++) b[opt + 0x40 + i] = 0;             // CheckSum
        long certLen = (long)BitConverter.ToUInt32(b, secEnt + 4);
        long certPtr = (long)BitConverter.ToUInt32(b, secEnt);
        for (int i = 0; i < 8; i++) b[secEnt + i] = 0;                 // security dir entry
        int end = (certLen > 0 && certPtr > 0 && certPtr < b.Length) ? (int)certPtr : b.Length;
        byte[] o = new byte[end];
        Array.Copy(b, o, end);
        outp = o;
        return true;
    }

    public static string HashAlg(byte[] d, string algo) {
        byte[] h = (algo == "sha1") ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d);
        return BitConverter.ToString(h).Replace("-", "");
    }

    public static byte[] HexPat(string h) {
        byte[] o = new byte[h.Length / 2];
        for (int i = 0; i < o.Length; i++) o[i] = Convert.ToByte(h.Substring(i * 2, 2), 16);
        return o;
    }

    public static List<string> Hits(string root, byte[] pat) {
        var res = new List<string>();
        if (!Directory.Exists(root)) return res;
        foreach (string f in Directory.GetFiles(root, "*.cat", SearchOption.TopDirectoryOnly)) {
            byte[] b;
            try { b = File.ReadAllBytes(f); } catch { continue; }
            int n = pat.Length, lim = b.Length - n;
            for (int i = 0; i <= lim; i++) {
                if (b[i] != pat[0]) continue;
                bool ok = true;
                for (int j = 1; j < n; j++) { if (b[i + j] != pat[j]) { ok = false; break; } }
                if (ok) { res.Add(Path.GetFileName(f)); break; }
            }
        }
        return res;
    }
}
'@

Write-Output ("elevated=" + [CatHash]::IsAdmin())
$roots = @(
    "$env:SystemRoot\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}",
    "$env:SystemRoot\System32\CatRoot\{127D0A1D-4EF2-11D1-8608-00C04FC295EE}"
)

foreach ($t in $Paths) {
    Write-Output ("=== " + $t)
    if (-not (Test-Path -LiteralPath $t)) { Write-Output "  MISSING"; continue }
    Write-Output ("  size=" + (Get-Item -LiteralPath $t).Length)
    Write-Output ("  raw-sha256=" + (Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash)
    $flat = $null
    if (-not [CatHash]::Flat($t, [ref]$flat)) { Write-Output "  flat: not PE / unreadable"; continue }
    foreach ($algo in @("sha1", "sha256")) {
        $pat = [CatHash]::HashAlg($flat, $algo)
        Write-Output ("  flat-" + $algo + "=" + $pat)
        $pb = [CatHash]::HexPat($pat)
        foreach ($r in $roots) {
            $hits = [CatHash]::Hits($r, $pb)
            Write-Output ("    [" + $algo + "] " + (Split-Path $r -Leaf) + " -> hits=" + $hits.Count + $(if ($hits.Count) { " :: " + ($hits -join ", ") } else { "" }))
            foreach ($hn in $hits) {
                $fp = Join-Path $r $hn
                $sx = Get-AuthenticodeSignature -LiteralPath $fp
                Write-Output ("        status=" + $sx.Status + " signer=" + $sx.SignerCertificate.Subject)
                if ($sx.SignerCertificate) {
                    $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                    $null = $ch.Build($sx.SignerCertificate)
                    foreach ($el in $ch.ChainElements) { Write-Output ("        chain: " + $el.Certificate.Subject) }
                }
            }
        }
    }
}
Write-Output "DONE"
