# p25h - Q1 (name-vs-key) retry with a CORRECT root builder, then the ground-truth kernel probe.
#
# ROOT CAUSE of p25g Sec1 (proved by p25h.diag2.txt V1/V5):
#   New-Cert2 passed -KeyUsage an X509KeyUsageFlags VALUE. A multi-flag value stringifies as
#   "CrlSign, KeyCertSign" (space + wrong casing) and Microsoft.CertificateServices.Commands.KeyUsage
#   cannot parse it -> ParameterBindingException -> New-SelfSignedCertificate returned nothing.
#   So every "spoof root" was missing and each "leaf" silently self-signed (Issued to = Issued by).
#   diag3 PROVED the real shape: -KeyUsage is KeyUsage[] (array of a NO-[Flags] enum) -> ONE NAME PER
#   ELEMENT. @('CertSign','CRLSign') = OK (KU=03-02-01-06); the joined string 'CertSign,CRLSign' = THREW;
#   an int 6 = THREW; single 'CertSign' = OK.
#   V2/V3 with no -KeyUsage get the NSC default a0 (NO keyCertSign) -> always set it explicitly.
# FIX: pass -KeyUsage as a STRING with exact casing, capture errors into the log, assert the root
#      exists + is self-issued + is trusted BEFORE signing, then re-ask Q1 and re-run the kernel probe.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25h.txt'
$log = Join-Path $PSScriptRoot 'run25h.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25h (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; elevated p25h writes p25h.txt'
  exit
}
"=== p25h MSROOT-DISCRIMINATOR-FIXED $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') PS=$($PSVersionTable.PSVersion) ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }
function WL($t){ W $t; L $t }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$sig = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$MyStore   = 'Cert:\LocalMachine\My'
$RootStore = 'Cert:\LocalMachine\Root'

########## helpers ##########
function Ext-Hex($c,$oid){ $e = $c.Extensions[$oid]; if($e){ return [BitConverter]::ToString($e.RawData) } else { return '(absent)' } }
function Sig-Info($c){ "issuer='{0}' subj='{1}' selfsigned={2} KU={3} BC={4}" -f $c.Issuer,$c.Subject,[bool]($c.Issuer -eq $c.Subject),(Ext-Hex $c '2.5.29.15'),(Ext-Hex $c '2.5.29.19') }
function New-Root($sub){
  $p = @{ CertStoreLocation=$MyStore; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048
          HashAlgorithm='SHA256'; Subject=$sub; NotAfter=(Get-Date).AddYears(20); Type='Custom'
          KeyUsage=@('CertSign','CRLSign')
          TextExtension=@('2.5.29.19={critical}{text}ca=1') }
  $ev = $null
  try { $c = New-SelfSignedCertificate @p -ErrorVariable ev -ErrorAction Stop }
  catch { W ("      ROOT THREW -> {0}" -f ($_.Exception.Message -replace '\s+',' ')); return $null }
  if($null -eq $c){ W ("      ROOT RETURNED NULL errvar=[{0}]" -f (($ev | ForEach-Object { $_.Exception.Message }) -join '; ')) }
  return $c
}
function New-Leaf($sub,$root){
  $p = @{ CertStoreLocation=$MyStore; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048
          HashAlgorithm='SHA256'; Subject=$sub; NotAfter=(Get-Date).AddYears(5); Type='Custom'
          KeyUsage=@('DigitalSignature')
          TextExtension=@('2.5.29.19={critical}{text}ca=0','2.5.29.37={text}1.3.6.1.5.5.7.3.3') }
  if($root){ $p.Signer = $root }
  $ev = $null
  try { $c = New-SelfSignedCertificate @p -ErrorVariable ev -ErrorAction Stop }
  catch { W ("      LEAF THREW -> {0}" -f ($_.Exception.Message -replace '\s+',' ')); return $null }
  if($null -eq $c){ W ("      LEAF RETURNED NULL errvar=[{0}]" -f (($ev | ForEach-Object { $_.Exception.Message }) -join '; ')) }
  return $c
}
function Trust($c,$tag){
  $cer = Join-Path $PSScriptRoot ('_p25h_{0}.cer' -f $tag)
  [void][System.IO.File]::WriteAllBytes($cer,[byte[]]$c.Export('Cert'))
  $r = ((& certutil.exe -f -addstore Root $cer 2>&1) -join ' ') -replace '\s+',' '
  $in = [bool](Get-ChildItem -LiteralPath ($RootStore + '\' + $c.Thumbprint) -ErrorAction SilentlyContinue)
  W ("      trust: root now in LocalMachine\Root = {0}" -f $in)
  if(-not $in){ W ("      certutil raw: {0}" -f $r) }
  return $in
}
function Kp($file){
  $v  = ((& $sig verify /v /kp $file 2>&1) -join "`n")
  $er = if($v -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $codes = @(($v -split "`n") | Where-Object { $_ -match '0x8[0-9A-Fa-f]{7}' } | ForEach-Object { ($_ -replace '.*?(0x8[0-9A-Fa-f]{7}).*','$1').Trim() } | Select-Object -Unique)
  $msg = @(($v -split "`n") | Where-Object { $_ -match 'SignTool Error|does not chain|terminated in a root' } | ForEach-Object { $_.Trim() } | Select-Object -First 2)
  return @{ er=$er; codes=($codes -join ','); msg=($msg -join ' / '); raw=$v }
}
function Keep-Useful($txt){
  @(($txt -split "`n") | Where-Object { $_ -match 'Issued to|Issued by|Error|error|SignTool|Chain|Signature|Version of|Hash of|Digest|The certificate' }) |
    ForEach-Object { '      ' + $_.Trim() } | Select-Object -First 24
}

########## 0: host / DSE state ##########
W '########## 0: host / DSE state ##########'
$cur = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
W ("  build: {0}.{1}" -f $cur.CurrentBuild,$cur.UBR)
foreach($l in @((& bcdedit.exe /enum '{current}' 2>&1) | Where-Object { $_ -match 'testsigning|nointegrity|description' })){ W ('  bcd: ' + $l.Trim()) }
W ("  secureboot firmware = {0}" -f $(try{ [string](Confirm-SecureBootUEFI) }catch{ 'n/a' }))
W ("  signtool            = {0}" -f $sig)
W ("  live driver sig     = {0}" -f ((Get-AuthenticodeSignature $sys).Status))
$S2ROOT = '1A5520EED6638BEC2A5EE297D3FF984B2CACF889'
W ("  S2 root in Root     = {0}" -f [bool](Get-ChildItem ($RootStore + '\' + $S2ROOT) -ErrorAction SilentlyContinue))
W ''

########## 1: builder self-check (proof the fix works before anything else) ##########
W '########## 1: builder self-check ##########'
$selftest = New-Root 'CN=ApexDrv p25h SelfTest CA (QwenKern)'
if($selftest){
  W ("      thumb={0}" -f $selftest.Thumbprint)
  W ("      {0}" -f (Sig-Info $selftest))
  $kuh = Ext-Hex $selftest '2.5.29.15'
  W ("      keyCertSign bit present = {0} (expect True)  self-issued = {1} (expect True)" -f [bool]($kuh -match '0?6$|86$'),[bool]($selftest.Issuer -eq $selftest.Subject))
} else { W '      SELF-CHECK FAILED - builder still broken, everything below is void' }
W ''

########## 2: Q1 - is the signtool /kp MS-root test name-based or key-based? ##########
W '########## 2: name-spoof family (Q1: name or key?) ##########'
$names = @(
  @{ tag='S6lan'; sub='CN=Microsoft Root Certificate Authority 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' },
  @{ tag='S7win'; sub='CN=Microsoft Windows Production PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' },
  @{ tag='S8old'; sub='CN=Microsoft Root Certificate Authority 2010, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' },
  @{ tag='S9msf'; sub='CN=Microsoft Root Authority, OU=Microsoft Corporation, OU=Copyright (c) 1997 Microsoft Corp.' },
  @{ tag='S13pad'; sub='CN=Microsoft Root Certificate Authority 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US ' },
  @{ tag='S14cn';  sub='CN=Microsoft Root Certificate Authority 2011' }
)
$spoof = @()
foreach($n in $names){
  W ("  --- spoof {0}" -f $n.tag)
  $r = New-Root $n.sub
  if(-not $r){ W '      root missing -> pair void'; W ''; continue }
  W ("      root {0}  self-issued={1}" -f $r.Thumbprint,[bool]($r.Issuer -eq $r.Subject))
  $trusted = Trust $r $n.tag
  $lf = New-Leaf ("CN={0} Leaf (QwenKern)" -f $n.tag) $r
  if(-not $lf){ W '      leaf missing -> pair void'; W ''; continue }
  W ("      leaf {0}" -f $lf.Thumbprint)
  W ("      leaf issuer = '{0}'" -f $lf.Issuer)
  W ("      leaf chains to our root = {0} (expect True)" -f [bool]($lf.Issuer -eq $r.Subject))
  $f = Join-Path $PSScriptRoot ('_p25h_{0}.sys' -f $n.tag)
  Copy-Item -LiteralPath $sys -Destination $f -Force
  $s = ((& $sig sign /v /sm /sha1 $lf.Thumbprint /fd SHA256 $f 2>&1) -join "`n")
  $se = if($s -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $v = Kp $f
  W ("      sign_errors={0}  kp_errors={1} codes=[{2}]" -f $se,$v.er,$v.codes)
  W ("      {0}" -f $v.msg)
  if($v.er -ne 0){ Keep-Useful $v.raw | Select-Object -First 6 | ForEach-Object { W $_ } }
  $spoof += [pscustomobject]@{ tag=$n.tag; leaf=$lf; root=$r; file=$f; kp=$v.er; trusted=$trusted }
  W ''
}
$win1 = @($spoof | Where-Object { $_.kp -eq 0 -and $_.trusted }) | Select-Object -First 1

W '  --- control: existing S2 chain (local root, MS root absent) ---'
$s2leaf = @(Get-ChildItem $MyStore | Where-Object { $_.Subject -match 'CN=ApexDrv S2 Leaf' }) | Select-Object -First 1
if($s2leaf){
  $f = Join-Path $PSScriptRoot '_p25h_S2ctl.sys'
  Copy-Item -LiteralPath $sys -Destination $f -Force
  & $sig sign /v /sm /sha1 $s2leaf.Thumbprint /fd SHA256 $f 2>&1 | Out-Null
  $v = Kp $f
  W ("  S2ctl kp_errors={0} codes=[{1}] {2}" -f $v.er,$v.codes,$v.msg)
}
W ''

########## 3: ground-truth kernel probe (sign live driver + sc cycle, testsigning stays OFF) ##########
W '########## 3: ground-truth probe (live driver, testsigning OFF) ##########'
$bak = 'C:\Windows\System32\drivers\apexdrv.sys.bak_p25h'
if(-not (Test-Path -LiteralPath $bak)){ Copy-Item -LiteralPath $sys -Destination $bak -Force; W ("  backup -> {0}" -f $bak) }
function Probe($cert,$label){
  W ("  --- probe {0} : signer {1}" -f $label,$cert.Subject)
  $s = ((& $sig sign /v /sm /sha1 $cert.Thumbprint /fd SHA256 $sys 2>&1) -join "`n")
  W ("  sign   : {0}" -f ((($s -split "`n") | Where-Object { $_ -match 'Successfully signed|Number of errors' }) -join ' | '))
  $lv = Kp $sys
  W ("  live /kp errors={0} codes=[{1}] {2}" -f $lv.er,$lv.codes,$lv.msg)
  Copy-Item -LiteralPath $sys -Destination 'C:\ProgramData\QwenKern\apexdrv.sys' -Force
  & sc.exe stop kernprobe | Out-Null
  & sc.exe delete kernprobe | Out-Null
  Start-Sleep -Milliseconds 700
  $sysQ = '"' + $sys + '"'
  W ("  create : {0}" -f (((& sc.exe create kernprobe type= kernel start= demand binPath= $sysQ DisplayName= 'ApexDrv kernprobe (p25h)' 2>&1) -join ' ').Trim()))
  $t0 = Get-Date
  W ("  start  : {0}" -f (((& sc.exe start kernprobe 2>&1) -join ' ').Trim()))
  Start-Sleep -Milliseconds 1400
  $qq = (((& sc.exe query kernprobe 2>&1) -join ' ').Trim()) -replace '\s+',' '
  W ("  query  : {0}" -f $qq)
  $running = [bool]($qq -match 'RUNNING')
  W ("  ===> {0} load = {1}" -f $label,$(if($running){'RUNNING (DSE accepted)'}else{'REFUSED'}))
  foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=$t0} -MaxEvents 3 -ErrorAction SilentlyContinue)){
    W ("     SCM {0} id={1} {2}" -f $e.TimeCreated.ToString('HH:mm:ss'),$e.Id,(($e.Message -split "`n")[0]))
  }
  foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=$t0} -MaxEvents 3 -ErrorAction SilentlyContinue)){
    W ("     CI  {0} id={1} {2}" -f $e.TimeCreated.ToString('HH:mm:ss'),$e.Id,(($e.Message -split "`n")[0]))
  }
  & sc.exe stop kernprobe | Out-Null
  W ''
  return [pscustomobject]@{ label=$label; cert=$cert; run=$running; kp=$lv.er }
}
$res = @()
if($win1){ $res += Probe $win1.leaf ('SPOOF-FIXED {0} (name = an MS root)' -f $win1.tag) }
elseif($spoof.Count){ $res += Probe $spoof[0].leaf ('spoof-fail control {0} (kp nonzero)' -f $spoof[0].tag) }
if($s2leaf){ $res += Probe $s2leaf 'S2 (local root control, known refused in p25g)' }
$won = @($res | Where-Object { $_.run }) | Select-Object -First 1
$refusedWithKp = @($res | Where-Object { -not $_.run -and $_.kp -ne 0 }).Count
$resolvedSame = @($res | Where-Object { ($_.run -and $_.kp -eq 0) -or ((-not $_.run) -and $_.kp -ne 0) }).Count -eq $res.Count

########## 4: VERDICT ##########
W ''
W '########## 4: VERDICT ##########'
$q1 = if($win1){ 'YES - /kp is NAME-based: a root we built with our OWN key passed the MS-root test purely by carrying an MS DN.' } else { 'NO - /kp is KEY-based: none of the 6 spoofed MS DNs satisfied the MS-root test.' }
$q2 = if($won){ 'YES - ci.dll accepted a LOCAL self-signed root with testsigning OFF.' } else { 'NO - ci.dll refused every chain; the kernel enforces the Microsoft-root rule here.' }
W ("  Q1 (/kp name vs key) -> {0}" -f $q1)
W ("  Q2 (kernel accepts local root?) -> {0}" -f $q2)
W ("  builder fixed? self-check root created = {0} (p25g had 0 roots created)" -f [bool]$selftest)
W ("  /kp faithfully predicted the kernel on all {0} probe(s) = {1}" -f $res.Count,$resolvedSame)
W ("  (fail-side load refusals that also had kp!=0: {0} - expected, this is the /kp proxy working)" -f $refusedWithKp)
foreach($p in $spoof){ W ("  spoof {0,-6} trusted={1} kp_errors={2} root={3}" -f $p.tag,$p.trusted,$p.kp,$(if($p.root){$p.root.Thumbprint}else{'(none)'})) }
W ''
if($won){
  W ("  *** LOADED, NO REBOOT NEEDED: {0} ***" -f $won.label)
  W ("  signer thumbprint = {0}" -f $won.cert.Thumbprint)
  @(("thumb=" + $won.cert.Thumbprint),
    ("label=" + $won.label),
    ("subject=" + $won.cert.Subject),
    ("issuer=" + $won.cert.Issuer),
    ("kp=0 and kernel load=RUNNING on build " + $cur.CurrentBuild + "." + $cur.UBR + " with testsigning=No"),
    ("cmd=signtool sign /v /sm /sha1 " + $won.cert.Thumbprint + " /fd SHA256 C:\Windows\System32\drivers\apexdrv.sys"),
    ("stage=Copy-Item -LiteralPath C:\Windows\System32\drivers\apexdrv.sys -Destination C:\ProgramData\QwenKern\apexdrv.sys -Force"),
    ("rollback=Copy-Item -LiteralPath C:\Windows\System32\drivers\apexdrv.sys.bak_p25g -Destination C:\Windows\System32\drivers\apexdrv.sys -Force")) |
    Set-Content -LiteralPath (Join-Path $PSScriptRoot '_p25h_winner.txt')
  W ("  winner -> {0}" -f (Join-Path $PSScriptRoot '_p25h_winner.txt'))
  W '  NEXT: point _index.txt:94 at this thumbprint, rebuild Apex + EAAC, re-verify with the SAME /kp + sc start pairing.'
} elseif($win1){
  W ('  /kp PASSED but the kernel still refused -> /kp is NOT the kernel rule.')
  W ('  NEXT fork: (A) keep gdrv3.sys, or (B) bcdedit /set testsigning on + reboot (keep the S2 shape).')
} else {
  W '  Q1 premise dead: a local root cannot masquerade as an MS root -> no-reboot path needs a shape change.'
  W '  NEXT fork: (A) keep gdrv3.sys (drop apexdrv), or (B) bcdedit /set testsigning on + reboot (S2 shape then always loads).'
}
W ''
W '  -- leftovers to sweep (junk leaves/roots from the p25g/p25h hunt) --'
foreach($c in @(Get-ChildItem $MyStore | Where-Object { $_.Subject -match 'S6lan|S7win|S8old|S9msf|S13pad|S14cn|p25h SelfTest|Probe v0|Lab DSE|S1 SelfSigned|S3 LeafNoBC|S4 LeafCA|S5 SelfSigned' } | Sort-Object Subject)){
  W ("    {0}  {1}" -f $c.Thumbprint,$c.Subject)
}
W '  -- ROLLBACK recipes --'
W '    driver  : Copy-Item -LiteralPath "C:\Windows\System32\drivers\apexdrv.sys.bak_p25g" -Destination "C:\Windows\System32\drivers\apexdrv.sys" -Force ; sc.exe stop kernprobe ; sc.exe delete kernprobe'
W '    certs   : certutil -delstore My <thumb> ; certutil -delstore Root <thumb>   (roots only untrusted after the driver is re-signed)'
"=== p25h END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Add-Content -LiteralPath $o
L ("p25h done {0} kp_win={1} kernel_win={2}" -f (Get-Date -f 'HH:mm:ss'),$(if($win1){$win1.tag}else{'none'}),$(if($won){$won.label}else{'none'}))
