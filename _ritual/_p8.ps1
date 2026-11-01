# _p8.ps1 -- ELEVATED decisive run.  Fixes the two defects that invalidated every earlier arm:
#   (1) _probe5/_p6 ran NON-elevated -> CatRoot writes + cryptsvc restart silently failed, so the
#       "unsigned cats never answer anything" result was an artifact of nothing being installed.
#   (2) CryptCATAdminAcquireContext2 was declared WITHOUT CharSet=CharSet.Unicode -> the
#       pwszHashAlgorithm string went out as ANSI, the UTF-16 read of "SHA1" is garbage ->
#       NTE_BAD_ALGID (0x80090008) -> every registration fell through to a legacy SHA-1 admin
#       context, so cryptsvc indexed only the 20-byte members.  That is precisely why a cat which
#       provably CONTAINS the driver's 32-byte sha256 (probe3: "@380 UP-OCTSTR len=32 37647B46..")
#       answers `sha1 osCatalog=apexdrv_p26.cat` and `sha256 osCatalog=NONE(err1168)`.
#
# Arms, each ended by a REAL cryptsvc index pass and a poll:
#   A  copy-only install (what p26_cat actually did)      -> expect sha1 hit / sha256 miss
#   B  plus AddCatalog under a SHA-256 admin context      -> expect sha256 HIT (the fix)
#   C  remove, then AddCatalog of the SIGNED cat under a SHA-256 context -> CI-eligible cat
# Verdict lines at the end name which arm made `sha256 osCatalog=` resolve.  writes _ritual\_p8.txt
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$out = Join-Path $d '_p8.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8 }
"=== _p8 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated=' + $elev)
$cl = Join-Path $d 'cateng.ps1'
$ctxt = Join-Path $d 'cateng.txt'
$st = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$F = 'C:\p8\f'
$cat = 'C:\p8\apexdrv_p8.cat'
New-Item -ItemType Directory -Path 'C:\p8' -Force | Out-Null

# 0. let a still-running _p6 finish (it shares cateng.txt)
$p6t = Join-Path $d '_p6.txt'
for ($i = 0; $i -lt 30; $i++) {
    if ((Test-Path -LiteralPath $p6t) -and ((Get-Content -LiteralPath $p6t -Raw) -match 'END-p6')) { break }
    Start-Sleep -Seconds 5
}
L ('_p6 finished=' + ((Test-Path -LiteralPath $p6t) -and ((Get-Content -LiteralPath $p6t -Raw) -match 'END-p6')))

function LastTwo {
    $a = '(no line)'; $b = '(no line)'
    foreach ($ln in (Get-Content -LiteralPath $ctxt -Tail 24)) {
        $m = [regex]::Match($ln, '^\s*sha1 osCatalog=(.+)$');   if ($m.Success) { $a = $m.Groups[1].Value.Trim() }
        $m = [regex]::Match($ln, '^\s*sha256 osCatalog=(.+)$'); if ($m.Success) { $b = $m.Groups[1].Value.Trim() }
    }
    return @($a, $b)
}
function Lookup([string]$tag) {
    & $cl -Path $drv -Alg sha1 -Lookup 2>&1 | Out-Null
    $r = LastTwo
    L ("[$tag] sha1=" + $r[0] + " | sha256=" + $r[1])
}
function Poll([string]$tag, [int]$n) { for ($i = 1; $i -le $n; $i++) { Lookup ($tag + '-p' + $i); Start-Sleep -Seconds 6 } }
function RestartC {
    & net.exe stop cryptsvc /y 2>&1 | Out-Null; Start-Sleep -Seconds 3
    & net.exe start cryptsvc 2>&1 | Out-Null; Start-Sleep -Seconds 5
    L ('  cryptsvc=' + (Get-Service cryptsvc).Status)
}
function Bytes([string]$hex) { $o = New-Object byte[] ($hex.Length / 2); for ($i = 0; $i -lt $o.Length; $i++) { $o[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }; $o }
function Off([byte[]]$b, [byte[]]$p) { for ($i = 0; $i -le $b.Length - $p.Length; $i++) { $m = $true; for ($j = 0; $j -lt $p.Length; $j++) { if ($b[$i + $j] -ne $p[$j]) { $m = $false; break } }; if ($m) { return $i } }; return -1 }
if (-not ('W' -as [type])) {
    Add-Type -Namespace '' -Name W -MemberDefinition @'
using System;
using System.Runtime.InteropServices;
[DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid sub, [MarshalAs(UnmanagedType.LPWStr)] string alg, IntPtr policy, uint flags);
[DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern IntPtr CryptCATAdminAddCatalog(IntPtr h, [MarshalAs(UnmanagedType.LPWStr)] string f, [MarshalAs(UnmanagedType.LPWStr)] string baseName, uint flags);
[DllImport("wintrust.dll", SetLastError=true)]
public static extern bool CryptCATAdminReleaseContext(IntPtr h, uint flags);
'@
}
function AddCat([string]$file, [string]$name, [string]$alg) {
    $h = [IntPtr]::Zero; $g = [Guid]'F750E6C3-38EE-11D1-85E5-00C04FC295EE'
    $ok = [W]::CryptCATAdminAcquireContext2([ref]$h, [ref]$g, $alg, [IntPtr]::Zero, 0)
    L ("  AcquireContext2($alg) ok=$ok h=$h err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    if (-not $ok -or $h -eq [IntPtr]::Zero) { return }
    $hc = [W]::CryptCATAdminAddCatalog($h, $file, $name, 0)
    L ("  AddCatalog($alg -> $name) h=$hc err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    if ($hc -ne [IntPtr]::Zero) { [void][W]::CryptCATAdminReleaseContext($hc, 0) }
    [void][W]::CryptCATAdminReleaseContext($h, 0)
    L ('  now in store=' + (Test-Path -LiteralPath (Join-Path $CATROOT $name)))
}
# 1. store ground truth, then wipe every amateur arm and prove the removal took effect
L '--- 1. CatRoot state / wipe ---'
Get-ChildItem -LiteralPath $CATROOT -Filter '*apexdrv*' -EA SilentlyContinue | ForEach-Object { L ('  pre ' + $_.Name + ' len=' + $_.Length) }
foreach ($p in @('apexdrv*', 'p29*', 'p26pr_*')) {
    Get-ChildItem -LiteralPath $CATROOT -Filter $p -EA SilentlyContinue | ForEach-Object {
        $f = $_.FullName; Remove-Item -LiteralPath $f -Force -EA SilentlyContinue
        L ('  rm ' + $_.Name + ' exists-after=' + (Test-Path -LiteralPath $f))
    }
}
RestartC
Lookup 'clean-store'

# 2. fresh 32-byte cat over the EXACT deployed bytes; report which hash fork each generator emitted
L '--- 2. generate ---'
New-Item -ItemType Directory -Path $F -Force | Out-Null
Copy-Item -LiteralPath $drv -Destination (Join-Path $F 'apexdrv.sys') -Force
Remove-Item -LiteralPath $cat -Force -EA SilentlyContinue
New-FileCatalog -Path $F -CatalogFilePath $cat -CatalogVersion 2 -ErrorAction SilentlyContinue | Out-Null
L ('  cat exists=' + (Test-Path -LiteralPath $cat) + ' len=' + $(if (Test-Path -LiteralPath $cat) { (Get-Item $cat).Length } else { 0 }))
$ciS1 = (([Security.Cryptography.SHA1]::Create()).ComputeHash([IO.File]::ReadAllBytes($drv)) | ForEach-Object { $_.ToString('X2') }) -join ''
$ciS2 = (([Security.Cryptography.SHA256]::Create()).ComputeHash([IO.File]::ReadAllBytes($drv)) | ForEach-Object { $_.ToString('X2') }) -join ''
$bits = ((Get-Content -LiteralPath $ctxt -Tail 12) | Select-String -Pattern '^\s*sha(1|256) engine=' | ForEach-Object { $_.Line.Trim() }) -join ' ; '
L ('  cateng engine lines: ' + $bits)
$b = [IO.File]::ReadAllBytes($cat)
L ('  cat length=' + $b.Length)
L ('  raw-sha1   ' + $ciS1 + ' -> ' + (Off $b (Bytes $ciS1)))
L ('  raw-sha256 ' + $ciS2 + ' -> ' + (Off $b (Bytes $ciS2)))

# 3. ARM A: copy-only install (the path p26_cat actually used)
L '--- ARM A: copy-only ---'
Copy-Item -LiteralPath $cat -Destination (Join-Path $CATROOT 'apexdrv_p8.cat') -Force
L ('  staged exists=' + (Test-Path -LiteralPath (Join-Path $CATROOT 'apexdrv_p8.cat')))
RestartC
Poll 'A-copy' 3

# 4. ARM B: register the same cat under a SHA-256 admin context (the fix)
L '--- ARM B: AddCatalog with a SHA-256 admin context ---'
AddCat (Join-Path $CATROOT 'apexdrv_p8.cat') 'apexdrv_p8.cat' 'SHA256'
Lookup 'B-instant'
RestartC
Poll 'B-add2' 3

# 5. ARM C: the SIGNED cat, registered under a SHA-256 context (what CI will actually trust)
L '--- ARM C: sign + SHA-256-context AddCatalog ---'
$thumb = (Get-AuthenticodeSignature -LiteralPath $drv).SignerCertificate.Thumbprint
L ('  driver signer thumb=' + $thumb)
$scat = 'C:\p8\apexdrv_p8s.cat'
Copy-Item -LiteralPath $cat -Destination $scat -Force
if ($thumb) { & $st sign /v /sm /fd sha256 /sha1 $thumb $scat 2>&1 | ForEach-Object { L ('  sign: ' + $_) } }
else { L '  no signer on the driver -> unsigned arm C' }
L ('  signed status=' + (Get-AuthenticodeSignature -LiteralPath $scat).Status)
Remove-Item -LiteralPath (Join-Path $CATROOT 'apexdrv_p8.cat') -Force -EA SilentlyContinue
AddCat $scat 'apexdrv_p8s.cat' 'SHA256'
AddCat $scat 'apexdrv_p8s.cat' 'SHA1'
RestartC
Poll 'C-signed' 4

# 6. verdict
L '--- VERDICT ---'
$ans = (Get-Content -LiteralPath $out | Select-String -Pattern 'sha256=apexdrv_p8s\.cat|sha256=apexdrv_p8\.cat' | Select-Object -Last 1)
if ($ans) { L ('  SHA-256 lookup RESOLVED to our cat -> ' + $ans.Line.Trim()) } else { L '  sha256 lookup still NONE -> inspect above' }
L ('  store now: ' + (((Get-ChildItem -LiteralPath $CATROOT -Filter '*apexdrv*' -EA SilentlyContinue).Name) -join ', '))
L 'END-p8'
