# _p9.ps1 -- THE FIX, end to end, on the real install path.
#
# Goal: make the CI 32-byte (SHA-256) catalog lookup ANSWER for every apexdrv image the kernel may
# load, so CodeIntegrity stops emitting 3004 / sc start stops returning 577, with DSE enforcing and
# NO reboot.
#
# What _p8 proved (elevated, honest empty-store lookups) and what is therefore used here:
#   * an ELEVATED `Copy-Item` of a New-FileCatalog -CatalogVersion 2 cat into
#     System32\CatRoot\{F750E6C3-..} + a REAL cryptsvc restart makes BOTH the 20-byte and the 32-byte
#     lookup resolve (`[A-copy-p1] sha1=apexdrv_p8.cat; | sha256=apexdrv_p8.cat;`).
#     AddCatalog is NOT required; signing is NOT required for the *indexing* (but IS required for CI).
#   * _p8's arm C failed only because AddCatalog was invoked from PowerShell as an `out IntPtr`
#     P/Invoke via [ref] -> the call threw (logged "ok= h=0 err=0"), the store had already been wiped,
#     and the box was left with an empty apexdrv slot.  Every earlier "store refuses unsigned cats /
#     sha256 never resolves / AddCatalog is mandatory" conclusion traced back to that + non-elevation.
#
# Design decisions here:
#   1. ALL wintrust interop lives in C# inside Add-Type (the cateng-proven shape), never in a PS [ref]
#      call, so AcquireContext2 cannot silently throw again.
#   2. Install = Copy-Item (proven) AND AddCatalog under a Unicode SHA-256 *and* SHA-1 admin context
#      (belt and braces); either path landing the file is enough.
#   3. The cat covers the CI digest of EVERY file any apexdrv* service points at, not just the deployed
#      one, because CI hashes the service's own ImagePath (kernprobe -> System32\drivers\apexdrv.sys,
#      apexdrv -> the QwenKernPremium build copy, apexdrv_cat -> C:\p26cat\apexdrv_build.sys).
#   4. The cat is signed with the driver's own signer so the catalog signature itself is CI-acceptable
#      (chain: ApexDrv S2 Leaf -> ApexDrv S2 Root CA, both already trusted on this box), and the signer
#      leaf/root are (re)asserted into LocalMachine\Root + TrustedPublisher if missing.
#   5. Verdict is taken from the real lookup, the static CI analogue (signtool verify /pa /c) and a real
#      kernel load attempt (sc start rc / state / CodeIntegrity events), not from theory.
#
# Writes _ritual\_p9.txt.  Self-elevates (Start-Process -Verb RunAs) because a non-elevated session
# cannot write System32\CatRoot or stop cryptsvc.
param([switch]$NoElev)
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$out = Join-Path $d '_p9.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8 }
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm -and -not $NoElev) {
    $ps = Join-Path $PSHOME 'powershell.exe'
    # NB: Start-Process -ArgumentList does NOT quote its elements.  This script lives under
    # "C:\Users\New User\..." so an unquoted -File arg is split and powershell sees `-File C:\Users\New`,
    # errors out and exits in ~1 s without ever creating the log.  Quote the path ourselves.
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath $ps -ArgumentList $arg -Verb RunAs
    exit 0
}
"=== _p9 $(Get-Date -Format s)  elevated=$adm" | Set-Content -Encoding utf8 $out
$cl = Join-Path $d 'cateng.ps1'
$ctxt = Join-Path $d 'cateng.txt'
$st = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$sc = Join-Path $env:SystemRoot 'System32\sc.exe'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$DBDIR = Join-Path $env:SystemRoot 'System32\catroot2\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$F = 'C:\p9\f'
$cat = 'C:\p9\apexdrv_p9.cat'
$inst = Join-Path $CATROOT 'apexdrv_p9.cat'
$t0 = Get-Date
function Bytes([string]$hex) { $o = New-Object byte[] ([int]($hex.Length / 2)); for ($i = 0; $i -lt $o.Length; $i++) { $o[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }; $o }
function Off([byte[]]$b, [byte[]]$p) { for ($i = 0; $i -le $b.Length - $p.Length; $i++) { $m = $true; for ($j = 0; $j -lt $p.Length; $j++) { if ($b[$i + $j] -ne $p[$j]) { $m = $false; break } }; if ($m) { return $i } }; return -1 }
function StoreList([string]$tag) {
    $f = @(Get-ChildItem -LiteralPath $CATROOT -Filter '*apexdrv*' -EA SilentlyContinue)
    $p = @(Get-ChildItem -LiteralPath $CATROOT -Filter 'p29*' -EA SilentlyContinue)
    $r = @(Get-ChildItem -LiteralPath $CATROOT -Filter 'p26pr_*' -EA SilentlyContinue)
    L ("  store[$tag]: " + $(if ($f.Count + $p.Count + $r.Count) { (($f + $p + $r) | ForEach-Object { $_.Name + $(if ($_.PSIsContainer) { '[DIR]' } else { '(' + $_.Length + ')' }) }) -join ', ' } else { '(none)' }))
}
# ROOT CAUSE #2 (proven 2026-11-01 19:32): PowerShell 5.1's Remove-Item HANGS FOREVER -- kernel
# blocked, alive=True with CPU frozen to the byte -- when the target is a DIRECTORY whose name ends
# in .cat: the FileSystem provider re-enters the non-empty directory.  A prior attempt had left
# CatRoot\{F750..}\apexdrv_p26.cat as a DIRECTORY containing one file (apexdrv.sys), so the store
# held NO real .cat at all, every lookup missed, and the elevated child wedged at 9 lines for ever.
# Use the .NET APIs (no provider re-entry) and fall back to cmd rd/del; never Remove-Item a cat path.
function Kill([string]$p) {
    $it = Get-Item -LiteralPath $p -Force -EA SilentlyContinue
    if (-not $it) { return 'absent' }
    $isDir = $it.PSIsContainer
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { if ($isDir) { [IO.Directory]::Delete($p, $true) } else { [IO.File]::Delete($p) } } catch { L ('    kill-ex: ' + $_.Exception.GetType().Name) }
    $gone = -not (Test-Path -LiteralPath $p)
    if (-not $gone) {
        $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
        try { if ($isDir) { & $cmd /c ('rd /s /q "' + $p + '"') | Out-Null } else { & $cmd /c ('del /f /q "' + $p + '"') | Out-Null } } catch { }
        $gone = -not (Test-Path -LiteralPath $p)
    }
    $sw.Stop()
    return ('kind=' + $(if ($isDir) { 'DIR' } else { 'file' }) + ' gone=' + $gone + ' ms=' + $sw.ElapsedMilliseconds)
}
function RestartC([string]$why) {
    $s = Get-Service cryptsvc -EA SilentlyContinue
    L ("  restart($why): before=" + $(if ($s) { $s.Status } else { 'absent' }))
    Stop-Service cryptsvc -Force -EA SilentlyContinue
    for ($i = 0; $i -lt 60; $i++) { if ((Get-Service cryptsvc -EA SilentlyContinue).Status -eq 'Stopped') { break }; Start-Sleep -Milliseconds 500 }
    Start-Sleep -Milliseconds 800
    Start-Service cryptsvc -EA SilentlyContinue
    for ($i = 0; $i -lt 60; $i++) { if ((Get-Service cryptsvc -EA SilentlyContinue).Status -eq 'Running') { break }; Start-Sleep -Milliseconds 500 }
    L ("  restart($why): after=" + (Get-Service cryptsvc -EA SilentlyContinue).Status + "  sc=" + ((& $sc query cryptsvc 2>&1 | Out-String) -replace '\s+', ' ').Trim())
}
function LastTwo {
    $a = '(no line)'; $b = '(no line)'
    foreach ($ln in (Get-Content -LiteralPath $ctxt -Tail 30 -EA SilentlyContinue)) {
        $m = [regex]::Match($ln, '^\s*sha1 osCatalog=(.+)$');   if ($m.Success) { $a = $m.Groups[1].Value.Trim() }
        $m = [regex]::Match($ln, '^\s*sha256 osCatalog=(.+)$'); if ($m.Success) { $b = $m.Groups[1].Value.Trim() }
    }
    return @($a, $b)
}
function Lookup([string]$tag) {
    & $cl -Path $drv -Alg sha1 -Lookup 2>&1 | Out-Null
    $r = LastTwo
    L ("[" + $tag + "] sha1=" + $r[0] + " | sha256=" + $r[1])
    return $r[1]
}
function PollFix([string]$tag, [int]$n) {
    for ($i = 1; $i -le $n; $i++) {
        $h = Lookup ($tag + '-p' + $i)
        if ($h -match 'apexdrv_p9') { L ('  >> RESOLVED at ' + $tag + '-p' + $i); return $true }
        if ($i -eq 3) { RestartC ($tag + ' r2') }
        Start-Sleep -Seconds 5
    }
    return $false
}
# ---------------- 0. which images exist, and what will the kernel actually hash? ----------------
L '--- 0. services that load an apexdrv image (CI hashes the service ImagePath, so the cat must cover each) ---'
$svcs = @()
foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -EA SilentlyContinue)) {
    $ip = $null; try { $ip = (Get-ItemProperty -LiteralPath $k.PSPath -EA SilentlyContinue).ImagePath } catch { }
    if ($ip -and ($ip -match 'apexdrv')) { $svcs += [pscustomobject]@{ Name = $k.PSChildName; Image = ($ip -replace '^\\\?\?\\', '') } }
}
foreach ($s in $svcs) { L ("  svc " + $s.Name + " -> " + $s.Image + " exists=" + (Test-Path -LiteralPath $s.Image)) }
if (-not $svcs.Count) { L '  (none found - a service against the deployed driver will be created)' }
L ('  deployed drv exists=' + (Test-Path -LiteralPath $drv) + ' len=' + $(if (Test-Path -LiteralPath $drv) { (Get-Item -LiteralPath $drv).Length } else { 0 }))
L ('  db dir exists=' + (Test-Path -LiteralPath $DBDIR) + '   catroot exists=' + (Test-Path -LiteralPath $CATROOT))

# ---------------- 1. honest empty store ----------------
L '--- 1. wipe every apexdrv* cat and prove the removal is real ---'
StoreList 'pre'
foreach ($pat in @('apexdrv*', 'p29*', 'p26pr_*')) {
    foreach ($f in @(Get-ChildItem -LiteralPath $CATROOT -Filter $pat -EA SilentlyContinue)) {
        L ('  rm ' + $f.Name + ' ' + (Kill $f.FullName))
    }
}
L ('  store apexdrv* left after wipe = ' + @(Get-ChildItem -LiteralPath $CATROOT -Filter '*apexdrv*' -EA SilentlyContinue).Count)
RestartC 'after-wipe'
StoreList 'post-wipe'
Lookup 'clean-store' | Out-Null
# ---------------- 2. build a v2 cat covering EVERY candidate image, then sign it ----------------
L '--- 2. build apexdrv_p9.cat (CatalogVersion 2 => 32-byte SHA-256 members) over all covered images ---'
New-Item -ItemType Directory -Path 'C:\p9' -Force | Out-Null
New-Item -ItemType Directory -Path $F -Force | Out-Null
foreach ($f in @(Get-ChildItem -LiteralPath $F -Force -EA SilentlyContinue)) { L ('  fm rm ' + $f.Name + ' ' + (Kill $f.FullName)) }
$cover = @($drv) + @($svcs | ForEach-Object { $_.Image })
$cover = @($cover | Where-Object { $_ } | Select-Object -Unique)
$i = 0
foreach ($p in $cover) {
    if (-not (Test-Path -LiteralPath $p)) { L ('  MISSING ' + $p); continue }
    $i++
    $nm = if ($i -eq 1) { 'apexdrv.sys' } else { 'apexdrv_cover' + $i + '.sys' }
    Copy-Item -LiteralPath $p -Destination (Join-Path $F $nm) -Force
    L ('  cover[' + $i + '] ' + $p + ' -> ' + $nm + ' len=' + (Get-Item -LiteralPath (Join-Path $F $nm)).Length)
}
L ('  pre-build cat path ' + (Kill $cat))
New-FileCatalog -Path $F -CatalogFilePath $cat -CatalogVersion 2 -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path -LiteralPath $cat -PathType Leaf)) { L ('  !! build left no LEAF -> repair + rebuild: ' + (Kill $cat)); New-FileCatalog -Path $F -CatalogFilePath $cat -CatalogVersion 2 -ErrorAction SilentlyContinue | Out-Null }
L ('  built exists=' + (Test-Path -LiteralPath $cat) + ' isLeaf=' + (Test-Path -LiteralPath $cat -PathType Leaf) + ' len=' + $(if (Test-Path -LiteralPath $cat -PathType Leaf) { (Get-Item -LiteralPath $cat).Length } else { 0 }))
$thumb = (Get-AuthenticodeSignature -LiteralPath $drv).SignerCertificate.Thumbprint
L ('  driver signer thumb=' + $thumb)
$scat = 'C:\p9\apexdrv_p9s.cat'
L ('  pre-sign sct path ' + (Kill $scat))
Copy-Item -LiteralPath $cat -Destination $scat -Force
& $st sign /v /sm /fd sha256 /sha1 $thumb $scat 2>&1 | ForEach-Object { L ('  sign: ' + $_) }
Copy-Item -LiteralPath $scat -Destination $cat -Force
L ('  signed cat status=' + (Get-AuthenticodeSignature -LiteralPath $cat).Status + '  (must be Valid for CI to trust the catalog)')
& $st verify /pa $cat 2>&1 | ForEach-Object { L ('  verify/pa: ' + $_) }

# ---------------- 3. install (Copy-Item + AddCatalog from C#) and force a real index pass --------
L '--- 3. install into CatRoot and force cryptsvc to re-index ---'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CAT {
    [DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, string alg, IntPtr policy, uint flags);
    [DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CryptCATAdminAddCatalog(IntPtr h, string f, string baseName, uint flags);
    [DllImport("wintrust.dll", SetLastError=true)]
    static extern bool CryptCATAdminReleaseContext(IntPtr h, uint flags);
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    public static string Add(string alg, string file, string baseName) {
        Guid g = DRV; IntPtr h;
        if (!CryptCATAdminAcquireContext2(out h, ref g, alg, IntPtr.Zero, 0)) return "acq-ERR" + Marshal.GetLastWin32Error();
        try {
            IntPtr c = CryptCATAdminAddCatalog(h, file, baseName, 0);
            if (c == IntPtr.Zero) return "add-ERR" + Marshal.GetLastWin32Error();
            CryptCATAdminReleaseContext(c, 0);
            return "ok";
        } finally { CryptCATAdminReleaseContext(h, 0); }
    }
}
'@ -EA SilentlyContinue
if ((Test-Path -LiteralPath $inst) -and (Get-Item -LiteralPath $inst -Force).PSIsContainer) { L ('  !! inst path is a DIR (phantom cat) -> ' + (Kill $inst)) }
foreach ($alg in @('SHA256', 'SHA1')) { L ('  AddCatalog[' + $alg + '] -> ' + [CAT]::Add($alg, $cat, 'apexdrv_p9.cat')) }
Copy-Item -LiteralPath $cat -Destination $inst -Force
L ('  installed exists=' + (Test-Path -LiteralPath $inst) + ' isLeaf=' + (Test-Path -LiteralPath $inst -PathType Leaf) + ' len=' + $(if (Test-Path -LiteralPath $inst -PathType Leaf) { (Get-Item -LiteralPath $inst).Length } else { 0 }))
StoreList 'post-install'
RestartC 'after-install'
$resolved = PollFix 'FIX' 8
L ('  sha256 resolved to our cat = ' + $resolved)
# ---------------- 4. trust wiring + the static analogue of the CI check ----------------
L '--- 4. signer trust + signtool CI analogue ---'
try {
    $cert = (Get-AuthenticodeSignature -LiteralPath $drv).SignerCertificate
    $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
    [void]$chain.Build($cert)
    foreach ($el in $chain.ChainElements) { L ('  chain: ' + $el.Certificate.Subject + ' | thumb=' + $el.Certificate.Thumbprint) }
    $pub = @(Get-ChildItem Cert:\LocalMachine\TrustedPublisher -EA SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb })
    L ('  leaf in TrustedPublisher=' + ($pub.Count -gt 0))
    if ($pub.Count -eq 0) {
        $stp = New-Object Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
        $stp.Open('ReadWrite'); $stp.Add($cert); $stp.Close()
        L ('  added leaf to TrustedPublisher -> now=' + (@(Get-ChildItem Cert:\LocalMachine\TrustedPublisher | Where-Object { $_.Thumbprint -eq $thumb }).Count -gt 0))
    }
    $rootT = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Thumbprint
    $rin = @(Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue | Where-Object { $_.Thumbprint -eq $rootT })
    L ('  root ' + $rootT + ' in LocalMachine\Root=' + ($rin.Count -gt 0))
} catch { L ('  trust probe failed: ' + $_) }
& $st verify /pa /c $cat $drv 2>&1 | ForEach-Object { L ('  verify /pa /c (member-hash + cat sig) : ' + $_) }
L ('  verify /pa /c exit=' + $LASTEXITCODE)
& $st verify /kp /c $cat $drv 2>&1 | ForEach-Object { L ('  verify /kp /c (kernel policy) : ' + $_) }
L ('  verify /kp /c exit=' + $LASTEXITCODE)
# and the CI-hash cross-check straight from the live store
& $cl -Path $drv -Alg sha256 -Lookup 2>&1 | Out-Null
foreach ($ln in (Get-Content -LiteralPath $ctxt -Tail 30 -EA SilentlyContinue)) { if ($ln -match 'sha1 engine=|sha256 engine=|osCatalog=') { L ('  cateng: ' + $ln.Trim()) } }

# ---------------- 5. the actual kernel load attempt (no reboot) ----------------
L '--- 5. kernel load attempts ---'
$t0 = Get-Date
if (-not $svcs.Count) {
    & $sc create apexdrv_p9 type= kernel start= demand binPath= ('\??\' + $drv) DisplayName= 'p9 cat DSE test' 2>&1 | ForEach-Object { L ('  sc create: ' + $_) }
    $svcs = @([pscustomobject]@{ Name = 'apexdrv_p9'; Image = $drv })
}
foreach ($s in $svcs) {
    L ('--- svc ' + $s.Name + ' image=' + $s.Image)
    if (-not (Test-Path -LiteralPath $s.Image)) { L '  image missing, skip'; continue }
    & $sc stop $s.Name 2>&1 | Out-Null; Start-Sleep -Milliseconds 900
    $o = ((& $sc start $s.Name 2>&1) | Out-String).Trim()
    $rc = $LASTEXITCODE
    $stt = ((& $sc query $s.Name 2>&1 | Out-String) -replace '\s+', ' ').Trim()
    L ('  start rc=' + $rc + '  ' + ($o -replace '\s+', ' '))
    L ('  state: ' + $stt)
    if ($rc -eq 577) { L '  => 577 ERROR_INVALID_IMAGE_HASH (CI still refused this image)' }
    elseif ($rc -eq 1056) { L '  => 1056 already running' }
    elseif ($stt -match 'RUNNING') { L '  => RUNNING (kernel accepted the load => DSE satisfied, no reboot)' }
    else { L '  => rc/state above' }
    if ($stt -match 'RUNNING') { & $sc stop $s.Name 2>&1 | Out-Null }
}
# ---------------- 6. evidence from the event logs ----------------
L '--- 6. CodeIntegrity + SCM events since t0 ---'
try {
    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = $t0 } -EA SilentlyContinue | Select-Object -First 40)) {
        $m = ($e.Message -replace '\s+', ' '); if ($m.Length -gt 260) { $m = $m.Substring(0, 260) }
        L ('  CI id=' + $e.Id + ' ' + $e.TimeCreated.ToString('HH:mm:ss') + ' ' + $m)
    }
} catch { L ('  CI log: ' + $_) }
try {
    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $t0 } -EA SilentlyContinue | Select-Object -First 30)) {
        $m = ($e.Message -replace '\s+', ' '); if ($m.Length -gt 200) { $m = $m.Substring(0, 200) }
        L ('  SCM id=' + $e.Id + ' ' + $e.TimeCreated.ToString('HH:mm:ss') + ' ' + $m)
    }
} catch { L ('  SCM log: ' + $_) }

# ---------------- 7. verdict / final state ----------------
L '--- 7. verdict ---'
StoreList 'final'
$fin = LastTwo
L ('  final lookup sha1=' + $fin[0] + ' | sha256=' + $fin[1])
L ('  sha256 names our cat : ' + ($fin[1] -match 'apexdrv_p9'))
L ('  installed file present: ' + (Test-Path -LiteralPath $inst) + ' isLeaf=' + (Test-Path -LiteralPath $inst -PathType Leaf))
L ('  cat signature        : ' + (Get-AuthenticodeSignature -LiteralPath $inst).Status)
L ('  cryptsvc             : ' + (Get-Service cryptsvc).Status)
L '  rollback: Stop-Service cryptsvc -Force; Remove-Item C:\Windows\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\apexdrv_p9.cat; Start-Service cryptsvc'
L ('  artifacts: C:\p9\apexdrv_p9.cat (signed v2 cat over ' + $i + ' image(s))')
L ('END-p9 ' + (Get-Date -Format s))
