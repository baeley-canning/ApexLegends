# catfind.ps1 - byte-scan every installed catalog for a given file hash.
# Read-only, non-elevated.  Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\catfind.ps1
# Scans CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE} and {127D0A1D-...}
# for sha256 AND sha1 of every file passed in $Targets.
param([string[]]$Targets = @("$env:SystemRoot\System32\drivers\gdrv3.sys"))

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;

public static class CatFind {
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
    public static byte[] Hex(string h) {
        byte[] o = new byte[h.Length / 2];
        for (int i = 0; i < o.Length; i++) o[i] = Convert.ToByte(h.Substring(i * 2, 2), 16);
        return o;
    }
}
'@

function fmtHits($h) { if ($h.Count -gt 0) { " :: " + ($h -join ", ") } else { "" } }

$roots = @(
    "$env:SystemRoot\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}",
    "$env:SystemRoot\System32\CatRoot\{127D0A1D-4EF2-11D1-8608-00C04FC295EE}"
)

foreach ($t in $Targets) {
    Write-Output ("=== " + $t)
    if (-not (Test-Path -LiteralPath $t)) { Write-Output "  MISSING"; continue }
    $f = Get-Item -LiteralPath $t
    $s256 = (Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash
    $s1 = (Get-FileHash -LiteralPath $t -Algorithm SHA1).Hash
    Write-Output ("  size=" + $f.Length + "  sha256=" + $s256)
    foreach ($pair in @(@("sha256", $s256), @("sha1", $s1))) {
        $pat = [CatFind]::Hex($pair[1])
        foreach ($r in $roots) {
            $hits = [CatFind]::Hits($r, $pat)
            Write-Output ("  [" + $pair[0] + "] " + $r + " -> hits=" + $hits.Count + (fmtHits $hits))
            foreach ($hn in $hits) {
                $fp = Join-Path $r $hn
                $sx = Get-AuthenticodeSignature -LiteralPath $fp
                Write-Output ("      status=" + $sx.Status + " signer=" + $sx.SignerCertificate.Subject)
                if ($sx.SignerCertificate) {
                    Write-Output ("      notAfter=" + $sx.SignerCertificate.NotAfter + " thumb=" + $sx.SignerCertificate.Thumbprint)
                    $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                    $null = $ch.Build($sx.SignerCertificate)
                    foreach ($el in $ch.ChainElements) { Write-Output ("      chain: " + $el.Certificate.Subject) }
                }
            }
        }
    }
}
Write-Output "DONE"
