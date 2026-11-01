# cathash.ps1
# (A) Discover which byte range the signature ACTUALLY covers. signtool prints
#     "Hash of file (sha1|sha256)"; brute-force 20 plausible definitions and report which
#     one equals it. signtool is ground truth; our own signed probe file is a control.
# (B) With the proven definition, byte-scan EVERY catalog store (CatRoot + CatRoot2,
#     recursive, *.cat AND the catdb index that CI enumeration actually reads).
# Read-only, non-elevated.
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\cathash.ps1 [file...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)
if (-not $Paths) {
    $Paths = @("$env:SystemRoot\System32\drivers\gdrv3.sys",
               "$env:SystemRoot\System32\drivers\tcpip.sys",
               "$env:SystemRoot\System32\drivers\apexdrv.sys",
               (Join-Path $PSScriptRoot '_p25h_S6lan.sys'))
}

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
    public static byte[] H2B(string h) {
        byte[] o = new byte[h.Length / 2];
        for (int i = 0; i < o.Length; i++) o[i] = Convert.ToByte(h.Substring(i * 2, 2), 16);
        return o;
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

    public static List<int> Scan(byte[] b, byte[][] pats, bool[] found) {
        var hit = new List<int>();
        for (int p = 0; p < pats.Length; p++) {
            if (found[p]) continue;
            byte[] pat = pats[p]; int n = pat.Length;
            int lim = b.Length - n;
            for (int i = 0; i <= lim; i++) {
                if (b[i] != pat[0]) continue;
                bool ok = true;
                for (int j = 1; j < n; j++) { if (b[i + j] != pat[j]) { ok = false; break; } }
                if (ok) { found[p] = true; hit.Add(p); break; }
            }
        }
        return hit;
    }
}
'@
$sig = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

Write-Output ("elevated=" + [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
Write-Output ("signtool=" + $sig)
Write-Output ''
Write-Output '########## A: which byte range does signtool hash? ##########'

$chosenVariant = $null
$targets = @()
foreach ($t in $Paths) {
    Write-Output ("=== " + $t)
    if (-not (Test-Path -LiteralPath $t)) { Write-Output '  MISSING'; continue }
    $names = New-Object 'System.Collections.Generic.List[string]'
    $vals  = [VH]::Variants($t, $names)
    if ($vals.Count -eq 0) { Write-Output '  not a parseable PE'; continue }
    $map = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { if ($names[$i] -and $vals[$i]) { $map[$vals[$i]] = $names[$i] } }
    for ($i = 0; $i -lt $names.Count; $i++) { if ($vals[$i]) { Write-Output ("  " + $names[$i].PadRight(24) + " " + $vals[$i]) } }

    $st = Get-AuthenticodeSignature -LiteralPath $t
    Write-Output ("  AuthSig: status=" + $st.Status + " type=" + $st.SignatureType + " signer=" + $st.SignerCertificate.Subject)

    if ($sig) {
        foreach ($mode in @('/pa', '/kp')) {
            $out = ((& $sig verify /v $mode $t 2>&1) -join "`n")
            foreach ($m in [regex]::Matches($out, 'Hash of file \((sha1|sha256)\):\s*([0-9A-Fa-f]+)')) {
                $algo = $m.Groups[1].Value; $hv = $m.Groups[2].Value.ToUpper()
                Write-Output ("  signtool " + $mode + " Hash of file (" + $algo + ") = " + $hv)
                if ($map.ContainsKey($hv)) {
                    Write-Output ("  >>> MATCH: signtool(" + $mode + ") == variant '" + $map[$hv] + "'")
                    if (-not $chosenVariant) { $chosenVariant = ($map[$hv] -replace '\.(sha1|sha256)$','') }
                } else { Write-Output '  !!! no variant reproduces that value' }
            }
            foreach ($ln in ($out -split "`n" | Where-Object { $_ -match 'does not chain|Number of errors|SignTool Error' })) {
                Write-Output ("  " + $mode + " msg: " + $ln.Trim())
            }
        }
    }
    $targets += [pscustomobject]@{ path=$t; names=$names; vals=$vals }
}
Write-Output ("chosenVariant=" + $(if ($chosenVariant) { $chosenVariant } else { 'NONE' }))
########## PHASE B: store scan with the proven definition ##########
Write-Output ''
Write-Output '########## B: catalog store scan ##########'
$defs = @()
if ($chosenVariant) { $defs += $chosenVariant } else { $defs += 'ck1_sec1_tocp'; $defs += 'ck1_sec1_cp8dn' }
Write-Output ("definitions tried: " + ($defs -join ', ') + $(if ($chosenVariant) { '  [PROVEN by signtool]' } else { '  [fallback]' }))

$patNames = New-Object 'System.Collections.Generic.List[string]'
$patHex   = New-Object 'System.Collections.Generic.List[string]'
foreach ($tg in $targets) {
    $leaf = Split-Path $tg.path -Leaf
    for ($i = 0; $i -lt $tg.names.Count; $i++) {
        $nm = $tg.names[$i]; $hv = $tg.vals[$i]
        if (-not $nm) { continue }
        $take = $false
        foreach ($d in $defs) { if ($nm -eq ($d + '.sha1') -or $nm -eq ($d + '.sha256')) { $take = $true } }
        if ($nm -eq 'ck0_sec0_full.sha256') { $take = $true }   # raw sha256 for contrast
        if ($take) { $patNames.Add($leaf + ' :: ' + $nm); $patHex.Add($hv) }
    }
}
$pats = @(); foreach ($h in $patHex) { $pats += , ([VH]::H2B($h)) }
$found = New-Object 'bool[]' $pats.Count
Write-Output ("patterns=" + $pats.Count)

$stores = @("$env:SystemRoot\System32\CatRoot", "$env:SystemRoot\System32\CatRoot2")
foreach ($s in $stores) {
    if (-not (Test-Path -LiteralPath $s)) { Write-Output ("store MISSING: " + $s); continue }
    Write-Output ''
    Write-Output ("=== layout of " + $s)
    foreach ($d in @(Get-ChildItem -LiteralPath $s -Directory -ErrorAction SilentlyContinue)) {
        $kids = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
        Write-Output ("  " + $d.Name + "  files=" + $kids.Count + " bytes=" + (($kids | Measure-Object Length -Sum).Sum))
        if ($kids.Count -le 24) { foreach ($k in $kids) { Write-Output ("      " + $k.FullName.Substring($s.Length) + "  " + $k.Length) } }
        else { foreach ($k in $kids) { if ($k.Name -match 'catdb|\.db$|\.xml$|\.stl$|\.cat$') { Write-Output ("      " + $k.FullName.Substring($s.Length) + "  " + $k.Length) } } }
    }
    $files = @(Get-ChildItem -LiteralPath $s -Recurse -File -ErrorAction SilentlyContinue)
    Write-Output ("=== scanning " + $files.Count + " file(s) in " + $s)
    foreach ($f in $files) {
        $b = $null
        try { $b = [IO.File]::ReadAllBytes($f.FullName) } catch { continue }
        $hits = [VH]::Scan($b, $pats, $found)
        foreach ($p in $hits) {
            Write-Output ("  HIT " + $f.FullName.Substring($s.Length) + "  size=" + $b.Length + "  [" + $patNames[$p] + "]")
        }
    }
}
Write-Output ''
Write-Output '-- pattern summary --'
for ($i = 0; $i -lt $pats.Count; $i++) { Write-Output ("  " + $(if ($found[$i]) { 'HIT ' } else { 'MISS' }) + " " + $patNames[$i]) }
Write-Output 'DONE'

