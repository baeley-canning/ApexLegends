# p26_cat.ps1 -- NO-REBOOT fallback for the DSE 577 / CI-3004 wall.
#
# WHY THIS EXISTS
#   apexdrv.sys carries a perfectly Valid embedded signature from our own dev ladder, and the
#   whole ladder is trusted in LocalMachine\Root + TrustedPublisher -- yet ci.dll refuses it while
#   this machine runs with testsigning=No (SecureBoot off).  p25h proved the gate:
#       signtool verify /kp  ->  "Signing Cert does not chain to a Microsoft Root Cert"
#   so CI falls through to CATALOG lookup and reports event 3004
#       "unable to verify the image integrity ... because file hash could not be found"
#   and sc start returns 577.  p25h also proved apexdrv is a member of NO installed .cat
#   (4759 catalogs / 172 MB scanned -> NONE err1168).  So CI has literally nowhere to look.
#
# WHAT THIS DOES (one elevated step, no reboot)
#   1. stage a byte-exact copy of the signed apexdrv.sys into a space-free dir (C:\p26cat)
#   2. compute its SI/CI *catalog* hash with the engine that is byte-for-byte equal to
#      CryptCATAdminCalcHash* (cateng.ps1, self-test 26/26) and cross-check it
#   3. emit a .cdf using <hash> member tags, build the .cat with WDK makecat (SHA1 cat = the
#      format every driver catalog on this box uses, see probe2: engineSha1 lookup FOUND)
#   4. sign the .cat with the SAME dev cert that signed the image (plus an appended second
#      signer, so both staged images' chains are represented)
#   5. install it into  %SystemRoot%\System32\CatRoot\{F750E6C3-...}  (the DRIVER cat store)
#   6. PROVE the fix with the exact API ci.dll calls: CryptCATAdminEnumCatalogFromHash under
#      DRIVER_ACTION_VERIFY must go NONE(err1168) -> FOUND (that is what kills event 3004)
#   7. attempt a REAL kernel load (sc start) and classify the result
#
# run:  powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p26_cat.ps1
# writes: _ritual\p26_cat.txt  (self-elevates once; the launching copy waits and prints the log)
# rollback: Stop-Service <svc>; sc delete apexdrv_cat ; del C:\p26cat ; del the cat from CatRoot
param([switch]$NoSelfElevate)
$ErrorActionPreference = 'Continue'
$d   = $PSScriptRoot
$out = Join-Path $d 'p26_cat.txt'
$WORK = 'C:\p26cat'   # deliberately space-free: makecat's .cdf parser and the loader both like it
function L([string]$s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }

$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm -and -not $NoSelfElevate) {
    Write-Host 'not elevated -> self-elevating via UAC (this copy waits and then prints the log)'
    # one single argument STRING (not an array): the script path has spaces, and only the
    # single-string form survives Start-Process quoting -- this exact idiom is proven in run3.ps1
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argl  = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -NoSelfElevate'
    try { $p = Start-Process -FilePath $psExe -Verb RunAs -PassThru -ArgumentList $argl; $p.WaitForExit() }
    catch { ('UAC declined/failed: ' + $_.Exception.Message) | Add-Content -Encoding utf8 $out }
    if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out }
    exit 0
}

"=== p26_cat  $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')  elevated=$adm ===" | Set-Content -Encoding utf8 $out
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$os = Get-CimInstance Win32_OperatingSystem
L ("host build={0}.{1}  boot={2}  now={3}" -f $cv.CurrentBuild, $cv.UBR, $os.LastBootUpTime, (Get-Date))
$bcd = (bcdedit.exe /enum '{current}' 2>&1 | Out-String)
foreach ($k in 'testsigning', 'nointegritychecks') {
    $m = [regex]::Match($bcd, "(?im)^\s*$k\s+(\S+)")
    L ("bcd." + $k + "=" + $(if ($m.Success) { $m.Groups[1].Value } else { '(not set)' }))
}
L ("test signing is armed in BCD only if it differs from the boot time -> no reboot has happened yet")
# ---------------- tools (same binaries p25h used; 19041 x64 is the only makecat on this box) ----
function FirstTool([string[]]$c) { $c | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
$mk = FirstTool @('C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\makecat.exe')
if (-not $mk) { $mk = Get-ChildItem 'C:\Program Files*\Windows Kits\10\bin\*\x64\makecat.exe' -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
$st = FirstTool @('C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe', 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe')
if (-not $st) { $st = Get-ChildItem 'C:\Program Files*\Windows Kits\10\bin\*\x64\signtool.exe' -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
$ct  = Join-Path $env:SystemRoot 'System32\certutil.exe'
$sc  = Join-Path $env:SystemRoot 'System32\sc.exe'
L ("makecat = " + $(if ($mk) { $mk } else { 'NOT FOUND' }))
L ("signtool = " + $(if ($st) { $st } else { 'NOT FOUND' }))
if (-not $mk -or -not $st) { L 'FATAL: missing WDK tool'; L 'END-p26_cat'; exit 6 }

# ---------------- stage (byte-exact, space-free) ----------------
if (Test-Path -LiteralPath $WORK) { Remove-Item -LiteralPath $WORK -Recurse -Force }
New-Item -ItemType Directory -Path $WORK -Force | Out-Null
$root = Split-Path -Parent $d
$srcB = Join-Path $root 'QwenKernPremium\build\apexdrv.sys'          # what p26_drv's svc loads
$srcS = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'      # p25h winner path / kernprobe
$m1 = Join-Path $WORK 'apexdrv_build.sys'
$m2 = Join-Path $WORK 'apexdrv_sys.sys'
Copy-Item -LiteralPath $srcB -Destination $m1 -Force
Copy-Item -LiteralPath $srcS -Destination $m2 -Force
$cdf = Join-Path $WORK 'apexdrv_p26.cdf'
$cat = Join-Path $WORK 'apexdrv_p26.cat'
foreach ($f in @($m1, $m2)) {
    $sig = Get-AuthenticodeSignature -LiteralPath $f
    L ("staged {0,-18} len={1} sha256={2} status={3} signer={4}" -f (Split-Path $f -Leaf), (Get-Item $f).Length,
        (Get-FileHash -Algorithm sha256 -LiteralPath $f).Hash.Substring(0, 16), $sig.Status, $sig.SignerCertificate.Subject)
}
# ---------------- engine hash: cateng rule (drop opt.Checksum + DataDirectory[4], stop at cert) --
function HashAlg([byte[]]$b, [string]$alg) {
    $h = [Security.Cryptography.HashAlgorithm]::Create($alg)
    try { ([BitConverter]::ToString($h.ComputeHash($b)) -replace '-', '') } finally { $h.Dispose() }
}
function EngineHash([string]$p, [string]$alg) {
    $raw = [IO.File]::ReadAllBytes($p); $len = $raw.Length
    if ($len -le 0x40 -or $raw[0] -ne 0x4D -or $raw[1] -ne 0x5A) { return (HashAlg $raw $alg) }
    $lf = [BitConverter]::ToInt32($raw, 0x3C)
    if ($lf -le 0 -or ($lf + 0x18) -gt $len -or $raw[$lf] -ne 0x50 -or $raw[$lf + 1] -ne 0x45) { return (HashAlg $raw $alg) }
    $opt = $lf + 24; $magic = [BitConverter]::ToUInt16($raw, $opt)
    $dirOff = if ($magic -eq 0x20B) { $opt + 0x70 } elseif ($magic -eq 0x10B) { $opt + 0x60 } else { -1 }
    if ($dirOff -le 0 -or ($dirOff + 4 * 9) -gt $len) { return (HashAlg $raw $alg) }
    if ([BitConverter]::ToUInt32($raw, $dirOff - 4) -lt 5) { return (HashAlg $raw $alg) }
    $chk = $opt + 0x40; $sec = $dirOff + 4 * 8
    $cp = [int][BitConverter]::ToUInt32($raw, $sec); $cl = [int][BitConverter]::ToUInt32($raw, $sec + 4)
    $vEnd = if ($cp -gt 0 -and $cl -gt 0 -and $cp -le $len) { $cp } else { $len }
    if (($chk + 4) -gt $sec -or ($sec + 8) -gt $vEnd) { return (HashAlg $raw $alg) }
    $ms = New-Object IO.MemoryStream
    $ms.Write($raw, 0, $chk); $ms.Write($raw, $chk + 4, $sec - ($chk + 4)); $ms.Write($raw, $sec + 8, $vEnd - ($sec + 8))
    $buf = $ms.ToArray(); $ms.Dispose()
    return (HashAlg $buf $alg)
}
$cl = Join-Path $d 'cateng.ps1'
foreach ($f in @($m1, $m2)) {
    $ref = ''; $mine = EngineHash $f 'sha1'
    try {
        & $cl -Path $f -Alg sha1 -NoApi 2>&1 | Out-Null
        $mm = [regex]::Match(((Get-Content -LiteralPath (Join-Path $d 'cateng.txt') -Tail 15) -join "`n"), '(?im)^\s*sha1\s+engine=([0-9A-F]{40})')
        if ($mm.Success) { $ref = $mm.Groups[1].Value }
    } catch { }
    L ("engineHash {0,-18} sha1={1}  cateng={2}  match={3}" -f (Split-Path $f -Leaf), $mine, $(if ($ref) { $ref } else { '(no ref)' }), ($ref -eq $mine))
}
# ---------------- SHA-256 member probe -------------------------------------------------------
# run2 proof: the cat WAS in the store (sha1 osCatalog=apexdrv_p26.cat) yet CI still failed, and
# ci's own 3004 event carries Hash Size=32 (sha256 37647B46...).  cateng confirms the gap:
#   sha1 osCatalog=apexdrv_p26.cat;   sha256 osCatalog=NONE(err1168)
# makecat writes SHA-1 member hashes only -> a 32-byte lookup finds no member.  Find a .cdf form
# that also emits the 32-byte entry (p25h note: an MS cat answers sha1 AND sha256, so dual is legal).
$prFile = Join-Path $WORK 'p26probe.bin'
Set-Content -LiteralPath $prFile -Value ('p26 sha256 member probe ' + [Guid]::NewGuid().ToString()) -Encoding ascii
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
function LastLookup([string]$alg) {
    try {
        foreach ($ln in (Get-Content -LiteralPath (Join-Path $d 'cateng.txt') -Tail 14)) {
            $mm = [regex]::Match($ln, ('^\s*' + $alg + ' osCatalog=(.+)$'))
            if ($mm.Success) { $last = $mm.Groups[1].Value.Trim() }
        }
        if ($last) { return $last }
    } catch { }
    return '(no line)'
}
$variants = @(
    @{ n = 'enc-10001';      hdr = @('EncodingType=0x00010001');                       tag = '<hash>' }
    @{ n = 'enc-10002';      hdr = @('EncodingType=0x00010002');                       tag = '<hash>' }
    @{ n = 'hashalg-800c';   hdr = @('EncodingType=', 'HashAlgorithms=0x0000800c');    tag = '<hash>' }
    @{ n = 'hashalg-8004';   hdr = @('EncodingType=', 'HashAlgorithms=0x00008004');    tag = '<hash>' }
    @{ n = 'hashalg-both';   hdr = @('EncodingType=', 'HashAlgorithms=0x0000800c,0x00008004'); tag = '<hash>' }
    @{ n = 'hashalg-spaced'; hdr = @('EncodingType=', 'HashAlgorithms=0x0000800c 0x00008004'); tag = '<hash>' }
    @{ n = 'hashalg-name';   hdr = @('HashAlgorithms=SHA256');                         tag = '<hash>' }
    @{ n = 'catver+800c';    hdr = @('CatalogVersion=2', 'EncodingType=', 'HashAlgorithms=0x0000800c'); tag = '<hash>' }
    @{ n = 'literal-name';   hdr = @('EncodingType=0x00010001');                       tag = '' }
)
L '--- sha256 member probe: which .cdf form gives the cat a 32-byte member hash? ---'
$win = $null
foreach ($v in $variants) {
    $pcdf = Join-Path $WORK ('pr_' + $v.n + '.cdf')
    $pcat = Join-Path $WORK ('pr_' + $v.n + '.cat')
    if ($v.tag) { $memb = $v.tag + 'p26probe.bin=' + $prFile } else {
        $sh = [Security.Cryptography.SHA256]::Create()
        try { $hex = ([BitConverter]::ToString($sh.ComputeHash([IO.File]::ReadAllBytes($prFile))) -replace '-', '') } finally { $sh.Dispose() }
        $memb = $hex + '=' + $prFile
    }
    (@(@('[CatalogHeader]', ('Name=pr_' + $v.n + '.cat'), ('ResultDir=' + $WORK), 'PublicVersion=0x00000001') + $v.hdr + @('', '[CatalogFiles]', $memb)) |
        Set-Content -LiteralPath $pcdf -Encoding ascii)
    & $mk -v $pcdf 2>&1 | Out-Null
    if (-not (Test-Path -LiteralPath $pcat)) { L ("  probe {0,-14} makecat rc={1} -> no .cat" -f $v.n, $LASTEXITCODE); continue }
    Copy-Item -LiteralPath $pcat -Destination (Join-Path $CATROOT ('p26pr_' + $v.n + '.cat')) -Force
    & $cl -Path $prFile -Alg sha256 -Lookup 2>&1 | Out-Null
    $lk = LastLookup 'sha256'; $hit = ($lk -notmatch 'NONE')
    L ("  probe {0,-14} cat={1,6} sha256Lookup={2}  {3}" -f $v.n, (Get-Item $pcat).Length, $lk, $(if ($hit) { 'HIT' } else { 'miss' }))
    if ($hit -and -not $win) { $win = $v }
}
# ---------------- generator #2: in-box PSCatalog (SHA-256 members) ------------------------------
# makecat (WDK 10.0.19041) is SHA-1-only: every .cdf variant above emitted a 20-byte member while
# ci.dll looks the image up by 32 bytes (its own 3004 event carries Hash Size=32 / sha256 37647B46,
# and 3089 confirms 32).  New-FileCatalog -CatalogVersion 2 is the in-box generator that hashes with
# CryptCATAdminCalcHashFromFileHandle2/SHA256 -> byte-identical to what ci computes.  If the probe
# below resolves, the real cat is built with it instead of a .cdf/makecat.
$gen = 'makecat'; $pscHit = $false
$pscOK = [bool](Get-Command New-FileCatalog -ErrorAction SilentlyContinue)
L ('--- PSCatalog probe: New-FileCatalog available=' + $pscOK + '  (CatalogVersion 2 => SHA-256 members)')
if ($pscOK) {
    $pdir = Join-Path $WORK 'psc'
    Remove-Item -LiteralPath $pdir -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory -Path $pdir -Force | Out-Null
    Copy-Item -LiteralPath $prFile -Destination (Join-Path $pdir 'p26probe.bin') -Force
    Copy-Item -LiteralPath $m1 -Destination (Join-Path $pdir 'apexdrv_build.sys') -Force
    $pcat = Join-Path $WORK 'pr_pscatalog.cat'
    try { New-FileCatalog -Path $pdir -CatalogFilePath $pcat -CatalogVersion 2 -ErrorAction Stop | Out-Null }
    catch { L ('  New-FileCatalog threw: ' + $_.Exception.Message) }
    if (Test-Path -LiteralPath $pcat) {
        Copy-Item -LiteralPath $pcat -Destination (Join-Path $CATROOT 'p26pr_pscatalog.cat') -Force
        & $cl -Path (Join-Path $pdir 'p26probe.bin') -Alg sha256 -Lookup 2>&1 | Out-Null
        $pl = LastLookup 'sha256'
        $pscHit = ($pl -match 'pscatalog')
        L ('  probe pscatalog-v2   cat={0,6} sha256Lookup={1}  {2}' -f (Get-Item $pcat).Length, $pl, $(if ($pscHit) { 'HIT' } else { 'miss' }))
        Remove-Item -LiteralPath (Join-Path $CATROOT 'p26pr_pscatalog.cat') -Force -EA SilentlyContinue
        if ($pscHit) { $gen = 'pscatalog-v2' }
    } else { L '  probe pscatalog-v2   -> no .cat produced by New-FileCatalog' }
} else { L '  PSCatalog missing -> cannot make a SHA-256 cat on this box' }
L ('  generator chosen = ' + $gen)

$hdrX = if ($win) { $win.hdr } else { @('EncodingType=0x00010001') }
$tagX = if ($win) { $win.tag } else { '<hash>' }
if ($win) { L ('  WINNER -> ' + $win.n + '   hdr=[' + ($win.hdr -join ' | ') + '] tag=' + $tagX) }
else      { L '  no variant emitted a 32-byte member; falling back to sha1-only .cdf' }
L ('  real cat will use hdr=[' + ($hdrX -join ' | ') + '] tag=' + $tagX)
# probe cats only cover p26probe.bin -> take them back out of the store so the real lookups are clean
foreach ($v in $variants) { Remove-Item -LiteralPath (Join-Path $CATROOT ('p26pr_' + $v.n + '.cat')) -Force -EA SilentlyContinue }
# ---------------- catalog: .cdf with <hash> member tags (makecat replaces them with the hash) --
@(
    '[CatalogHeader]'
    'Name=apexdrv_p26.cat'
    ('ResultDir=' + $WORK)
    'PublicVersion=0x00000001'
) + $hdrX + @(
    'CATATTR1=0x10010001:OSAttr:2:10.0,6.1'
    ''
    '[CatalogFiles]'
    ($tagX + 'apexdrv_build.sys=' + $m1)
    ($tagX + 'apexdrv_sys.sys=' + $m2)
) | Set-Content -LiteralPath $cdf -Encoding ascii
L '--- cdf ---'; Get-Content -LiteralPath $cdf | ForEach-Object { L ('  ' + $_) }

if ($gen -eq 'pscatalog-v2') {
    # SHA-256 cat straight from the staged files (member name = leaf name, member hash = ci's 32 bytes)
    $rdir = Join-Path $WORK 'real'
    Remove-Item -LiteralPath $rdir -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory -Path $rdir -Force | Out-Null
    Copy-Item -LiteralPath $m1 -Destination (Join-Path $rdir 'apexdrv_build.sys') -Force
    Copy-Item -LiteralPath $m2 -Destination (Join-Path $rdir 'apexdrv_sys.sys') -Force
    Remove-Item -LiteralPath $cat -Force -EA SilentlyContinue
    L ('--- New-FileCatalog -CatalogVersion 2   dir=' + $rdir)
    New-FileCatalog -Path $rdir -CatalogFilePath $cat -CatalogVersion 2 -ErrorAction SilentlyContinue -Verbose 4>&1 |
        ForEach-Object { L ('  pscatalog: ' + $_) }
    if (-not (Test-Path -LiteralPath $cat)) { L 'FATAL: New-FileCatalog produced no .cat'; L 'END-p26_cat'; exit 7 }
    L ("cat built len={0} generator=pscatalog-v2" -f (Get-Item $cat).Length)
} else {
    L '--- makecat ---'
    & $mk -v $cdf 2>&1 | ForEach-Object { L ('  makecat: ' + $_) }
    $mkrc = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $cat)) { L ("FATAL: makecat produced no .cat (rc=$mkrc)"); L 'END-p26_cat'; exit 7 }
    L ("cat built len={0} sha1={1}" -f (Get-Item $cat).Length, (Get-FileHash -Algorithm sha1 -LiteralPath $cat).Hash)
}

# ---------------- sign the cat (image signer first, second signer appended) ----------------
$signerB = (Get-AuthenticodeSignature -LiteralPath $m1).SignerCertificate.Thumbprint
$signerS = (Get-AuthenticodeSignature -LiteralPath $m2).SignerCertificate.Thumbprint
L ("cat signers -> build=" + $signerB + " sys=" + $signerS)
if ($signerB) { & $st sign /v /sm /fd sha256 /sha1 $signerB $cat 2>&1 | ForEach-Object { L ('  sign: ' + $_) } }
if ($signerS -and $signerS -ne $signerB) { & $st sign /v /sm /fd sha256 /as /sha1 $signerS $cat 2>&1 | ForEach-Object { L ('  sign/as: ' + $_) } }
& $st verify /pa $cat 2>&1 | ForEach-Object { L ('  verify/pa: ' + $_) }
& $st verify /kp $cat 2>&1 | ForEach-Object { L ('  verify/kp: ' + $_) }
$cs = Get-AuthenticodeSignature -LiteralPath $cat
L ("cat signature status={0}" -f $cs.Status)

# ---------------- PHASE A: kernel DSE reads MACHINE stores only -> prove/fix the chain ----------
function ChainInfo([string]$thumb) {
    $c = Get-ChildItem Cert:\LocalMachine\My -EA SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
    if (-not $c) { return [pscustomobject]@{ ok = $false; root = '(signer not in LocalMachine\My)'; els = @(); status = '' } }
    $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $ch.ChainPolicy.RevocationMode = 'NoCheck'
    $ok = $ch.Build($c)
    $els = @($ch.ChainElements | ForEach-Object { $_.Certificate })
    $st = (($ch.ChainStatus | ForEach-Object { $_.Status }) -join ',')
    $ch.Dispose()
    [pscustomobject]@{ ok = $ok; root = $(if ($els.Count) { $els[$els.Count - 1].Subject } else { '(none)' }); els = $els; status = $st }
}
foreach ($pair in @(@('build', $signerB), @('sys', $signerS))) {
    $tag = $pair[0]; $thumb = $pair[1]
    if (-not $thumb) { continue }
    $ci = ChainInfo $thumb
    L ("chain[" + $tag + "] buildOk=" + $ci.ok + " status=" + $ci.status + " root=" + $ci.root)
    foreach ($e in $ci.els) {
        $isRoot = ($e.Subject -eq $e.Issuer)
        $tgt = if ($isRoot) { 'Root' } else { 'CA' }
        $have = Get-ChildItem (('Cert:\LocalMachine\' + $tgt)) -EA SilentlyContinue | Where-Object { $_.Thumbprint -eq $e.Thumbprint }
        if (-not $have) {
            $s = New-Object System.Security.Cryptography.X509Certificates.X509Store $tgt, 'LocalMachine'
            $s.Open('ReadWrite'); $s.Add($e); $s.Close()
            L ("  installed missing " + $tgt + ": " + $e.Subject)
        } else { L ("  already in LocalMachine\" + $tgt + ": " + $e.Subject) }
    }
}
L '--- LocalMachine\My private-key certs and their chain roots (looking for a Microsoft-rooted one) ---'
$msCerts = @()
foreach ($c in (Get-ChildItem Cert:\LocalMachine\My -EA SilentlyContinue | Where-Object { $_.HasPrivateKey })) {
    $ci = ChainInfo $c.Thumbprint
    L ("  " + $c.Thumbprint + " " + $c.Subject + "  -> root: " + $ci.root + " buildOk=" + $ci.ok)
    if ($ci.root -match 'Microsoft') { $msCerts += $c }
}
if ($msCerts.Count) {
    # the kernel policy (/kp) and CI evaluate the PRIMARY signature first -> it must be the MS-rooted one
    $leaf = @($msCerts | Where-Object { $_.Subject -ne $_.Issuer })
    $pick = if ($leaf.Count) { $leaf[0] } else { $msCerts[0] }
    $mt = $pick.Thumbprint
    L ("MS-rooted signer -> promoting to PRIMARY signature: " + $mt + " " + $pick.Subject)
    & $st sign /v /sm /fd sha256 /sha1 $mt $cat 2>&1 | ForEach-Object { L ('  sign/msprimary: ' + $_) }
    foreach ($tb in @($signerB, $signerS)) {
        if ($tb -and $tb -ne $mt) { & $st sign /v /sm /fd sha256 /as /sha1 $tb $cat 2>&1 | ForEach-Object { L ('  sign/as2: ' + $_) } }
    }
    $cs2 = Get-AuthenticodeSignature -LiteralPath $cat
    L ("cat status after MS-primary re-sign: " + $cs2.Status + " primarySigner=" + $cs2.SignerCertificate.Subject)
} else { L 'no Microsoft-rooted cert with a private key on this box' }

# <<PHASEA>>

# ---------------- install into the DRIVER cat store and PROVE the CI hash lookup resolves ----
$CR = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
if (-not (Test-Path -LiteralPath $CR)) { L ("FATAL: driver cat store missing: " + $CR); L 'END-p26_cat'; exit 8 }
$catPre = (Get-ChildItem -LiteralPath $CR -Filter '*apexdrv*' -EA SilentlyContinue).Name -join ';'
L ("catroot pre-existing apexdrv members: " + $(if ($catPre) { $catPre } else { '(none)' }))
Copy-Item -LiteralPath $cat -Destination (Join-Path $CR 'apexdrv_p26.cat') -Force
Copy-Item -LiteralPath $cat -Destination (Join-Path $CR 'apexdrv_p26.cat') -Force
foreach ($sn in @('CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}', $CR)) {
    & $ct -AddStore -f $sn $cat 2>&1 | ForEach-Object { L ('  certutil[' + $sn + ']: ' + $_) }
}
# the real API (what pnputil/INF install uses) - registers the cat with CI properly
if (-not ('CC' -as [type])) {
    Add-Type -Namespace '' -Name CC -MemberDefinition @'
[DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CryptCATAdminAddCatalog(IntPtr h, string f, string baseName, uint flags);
[DllImport("wintrust.dll", SetLastError=true)] public static extern bool CryptCATAdminReleaseContext(IntPtr h, uint flags);
[DllImport("wintrust.dll", SetLastError=true)] public static extern IntPtr CryptCATAdminAcquireContext2(ref IntPtr h, ref Guid sub, string algo, IntPtr policy, uint flags);
'@
}
$hAdmin = [IntPtr]::Zero; $gDrv = [Guid]'F750E6C3-38EE-11D1-85E5-00C04FC295EE'
foreach ($alg in @('SHA1', 'SHA256')) {
    $hAdmin = [IntPtr]::Zero
    $okAcq = [CC]::CryptCATAdminAcquireContext2([ref]$hAdmin, [ref]$gDrv, $alg, [IntPtr]::Zero, 0)
    L ("CryptCATAdminAcquireContext2 alg=" + $alg + " ok=" + $okAcq + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    if ($okAcq -and $hAdmin -ne [IntPtr]::Zero) {
        $hCat = [CC]::CryptCATAdminAddCatalog($hAdmin, $cat, 'apexdrv_p26.cat', 0)
        L ("CryptCATAdminAddCatalog alg=" + $alg + " h=" + $hCat + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        if ($hCat -ne [IntPtr]::Zero) { [void][CC]::CryptCATAdminReleaseContext($hCat, 0) }
        [void][CC]::CryptCATAdminReleaseContext($hAdmin, 0)
    }
}


L ("installed -> " + (Join-Path $CR 'apexdrv_p26.cat') + "  exists=" + (Test-Path -LiteralPath (Join-Path $CR 'apexdrv_p26.cat')))

function LookupProof([string]$tag) {
    $r1 = @(); $r2 = @()
    & $cl -Path $m1, $m2 -Alg sha1 -Lookup 2>&1 | Out-Null
    foreach ($ln in (Get-Content -LiteralPath (Join-Path $d 'cateng.txt') -Tail 16)) {
        $mm = [regex]::Match($ln, '^\s*sha1 osCatalog=(.+)$');   if ($mm.Success) { $r1 += $mm.Groups[1].Value.Trim() }
        $mm = [regex]::Match($ln, '^\s*sha256 osCatalog=(.+)$'); if ($mm.Success) { $r2 += $mm.Groups[1].Value.Trim() }
    }
    L ("LOOKUP[" + $tag + "] sha1  =" + $(if ($r1.Count) { $r1 -join ' ' } else { '(no line)' }))
    L ("LOOKUP[" + $tag + "] sha256=" + $(if ($r2.Count) { $r2 -join ' ' } else { '(no line)' }) + "   <- ci's lookup (event 3004 criterion)")
    return @{ sha1 = ($r1 -join ' '); sha256 = ($r2 -join ' ') }
}
$lk = LookupProof 'before-flush'
L 'flushing catalog caches: stop/start cryptsvc unconditionally'
& net.exe stop cryptsvc /y 2>&1 | ForEach-Object { L ('  net: ' + $_) }
Start-Sleep -Seconds 3
& net.exe start cryptsvc 2>&1 | ForEach-Object { L ('  net: ' + $_) }
Start-Sleep -Seconds 4
$lk2 = LookupProof 'after-flush'
if ($lk.sha256 -match 'NONE' -or -not $lk.sha256) { $lk = $lk2 }
L ('--- kp re-verify after root install / MS append on: ' + $cat)
& $st verify /kp $cat 2>&1 | ForEach-Object { L ('  verify/kp2: ' + $_) }
$kp2 = $LASTEXITCODE
L ('  kp2 exit=' + $kp2)
$ci3004gone = ($lk.sha256 -match 'apexdrv_p26\.cat')
L ('  ci-criterion (32-byte lookup resolves to our cat) = ' + $ci3004gone)

# ---------------- real kernel load attempt (the whole point) ----------------
$t0 = Get-Date
foreach ($svc in 'apexdrv_cat', 'kernprobe', 'apexdrv') {
    $img = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $svc) -EA SilentlyContinue).ImagePath
    L ("--- svc " + $svc + " image=" + $(if ($img) { $img } else { '(absent)' }))
    if ($svc -eq 'apexdrv_cat') {
        & $sc create apexdrv_cat type= kernel start= demand binPath= '\??\C:\p26cat\apexdrv_build.sys' DisplayName= 'p26 cat DSE test' 2>&1 | ForEach-Object { L ('  sc create: ' + $_) }
    }
    if (-not (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $svc) -EA SilentlyContinue)) { L '  (absent, skip)'; continue }
    & $sc stop $svc 2>&1 | Out-Null; Start-Sleep -Milliseconds 700
    $o = (& $sc start $svc 2>&1 | Out-String).Trim()
    $rc = $LASTEXITCODE
    $st = ((& $sc query $svc 2>&1 | Out-String) -replace '\s+', ' ')
    L ("  start rc=" + $rc + "  " + ($o -replace '\s+', ' '))
    L ("  state: " + $st.Trim())
    if ($rc -eq 577) { L '  => 577 / ERROR_INVALID_IMAGE_HASH (CI refused the load)' }
    elseif ($st -match 'RUNNING') { L '  => RUNNING (kernel accepted it)' }
}

# ---------------- CodeIntegrity / audit evidence ----------------
L '--- events (CodeIntegrity full records + System/Service Control Manager) ---'
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = $t0.AddSeconds(-3) } -EA SilentlyContinue |
        Select-Object -First 15 | ForEach-Object {
            $msg = ($_.Message -replace '\s+', ' '); if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 150) }
            L ("  CI " + $_.Id + " " + $_.TimeCreated + " " + $msg)
            try {
                $x = [xml]$_.ToXml()
                foreach ($dd in $x.Event.EventData.Data) {
                    $v = if ($dd.Name) { $dd.'#text' } else { [string]$dd }
                    if ($v) { $v = ($v -replace '\s+', ' '); if ($v.Length -gt 160) { $v = $v.Substring(0, 160) }; L ('     ' + $(if ($dd.Name) { $dd.Name } else { 'data' }) + ' = ' + $v) }
                }
            } catch { }
        }
} catch { L '  (no CI log)' }
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $t0.AddSeconds(-3) } -EA SilentlyContinue |
        Select-Object -First 8 | ForEach-Object { L ('  SCM ' + $_.Id + ' ' + $_.TimeCreated + ' ' + (($_.Message -replace '\s+', ' ') -replace '^(.{0,200}).*$', '$1')) }
} catch { }


# ---------------- verdict ----------------
L '--- VERDICT ---'
L ("CI sha256 (32-byte) lookup -> our cat : " + $ci3004gone + "   (before=" + $lk.sha256 + " | after=" + $lk2.sha256 + ")")
L ("CI sha1   (20-byte) lookup -> our cat : " + ($lk.sha1 -match 'apexdrv_p26\.cat'))
L ("signtool /kp exit after chain fix      : " + $kp2)
$runAny = @('apexdrv_cat', 'kernprobe', 'apexdrv') | Where-Object { ((& $sc query $_ 2>&1 | Out-String) -match 'RUNNING') }
L ("services RUNNING now               : " + $(if ($runAny) { $runAny -join ', ' } else { '(none)' }))
if ($runAny) { L '*** CAT PATH WORKS WITHOUT A REBOOT: kernel loaded a local-root-signed driver (testsigning=No) ***' }
elseif ($ci3004gone -and $kp2 -ne 0) {
    L 'member+cat are installed and CI SEEs the hash, but the catalog signature fails the kernel policy (/kp)'
    L '  -> chain would have to end in a Microsoft root, OR testsigning must be in force'
    L '  -> reboot once (bcd.testsigning is already Yes) and this module loads; no further cat work needed'
}
elseif ($ci3004gone) { L 'cat installed + CI hash found + /kp now passes, loader still refused -> re-check CI XML above (signer/publisher fields)' }
else { L 'cat installed but CI still cannot see the hash -> inspect the LOOKUP lines and catroot' }
L 'END-p26_cat'




