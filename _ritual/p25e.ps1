# p25e - AK shape hunt. p25/p25c/p25d narrowed it to:
#   * keyUsage on the CA is CORRECT (raw 03-02-01-86 = digitalSignature|keyCertSign|cRLSign)
#   * BC is present, critical, cA=TRUE (p25c read it via the typed .CertificateAuthority property)
#   * yet /kp still returns 0x80096019 "basic constraint extension has not been observed"
#   * p25d invented a second reader bug: X509BasicConstraintsExtension/KeyUsageExtension need
#     (rawData[, critical]) - single-arg ::new() threw -> catch -> cA=False -> 0 candidates.
# So: decode with certutil as ground truth, then test the SHAPES the kernel AK policy expects.
#   S1 self-signed CA (BC ca=1 crit + KU CertSign + EKU codesign)      <- p25 fallback shape, known fail
#   S2 root(BC ca=1 crit, KU CertSign, no EKU) + leaf(BC ca=0 crit, KU digitalSignature, EKU codesign)
#   S3 like S2 leaf but with NO BC extension at all (MS-style leaf)
#   S4 like S2 leaf but BC ca=1 (makecert-style leaf)
#   S5 S1 without EKU on the CA
# First /kp with 0 errors signs the live driver; full verbose chain output is captured unpiped.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25e.txt'
$log = Join-Path $PSScriptRoot 'run25e.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25e (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; elevated p25e writes p25e.txt'
  exit
}
"=== p25e AK SHAPE HUNT $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') PS=$($PSVersionTable.PSVersion) ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }
function WL($t){ W $t; L $t }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$signtool = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$KU  = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]
$OID = [System.Security.Cryptography.Oid]
$BCX = [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]
$KUX = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]
$ASN = [System.Security.Cryptography.AsnEncodedData]

########## 0: ground-truth decoders (certutil) + fixed managed decoders ##########
function KU-Hex($c){ $e = $c.Extensions['2.5.29.15']; if($e){ return [BitConverter]::ToString($e.RawData) } else { return '(absent)' } }
function KU-Typed($c){
  # primary: the extension object is usually already typed; fallback: bake it from raw with the (raw,critical) ctor
  $e = $c.Extensions['2.5.29.15']; if(-not $e){ return $null }
  try { $x = $e; $null = $x.KeyUsages; return $x } catch {}
  try { return $KUX::new($ASN::new($OID::new('2.5.29.15'),[byte[]]$e.RawData),$e.Critical) } catch { return $null }
}
function CertSign($c){
  $x = KU-Typed $c
  if($x){ return [bool]($x.KeyUsages.ToString() -match 'KeyCertSign') }
  $d = $c.Extensions['2.5.29.15'].RawData
  $un = $d[2]; $by = $d[3]
  if($un -eq 0){ return (($by -band 0x04) -ne 0) }
  # bit 5 counted from the MSB of the first significant byte -> 0x04 in the LAST byte when unused<=3
  return (($by -band 0x04) -ne 0)
}
function CaOf($c){
  $e = $c.Extensions['2.5.29.19']; if(-not $e){ return 'absent' }
  try { return [string]$e.CertificateAuthority } catch {}
  try { return [string]$BCX::new($ASN::new($OID::new('2.5.29.19'),[byte[]]$e.RawData),$e.Critical).CertificateAuthority } catch { return '?' }
}
function Sig-Info($c){
  return ("ku_raw={0} certSign={1} BC={2} crit={3} EKU={4} selfSigned={5}" -f (KU-Hex $c),(CertSign $c),(CaOf $c),$c.Extensions['2.5.29.19'].Critical,(($c.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ','),($c.Subject -eq $c.Issuer))
}
function Certutil-Dump($c,$tag){
  if(-not $c){ W ("  --- certutil -dump {0}: no cert" -f $tag); return }
  $cer = Join-Path $PSScriptRoot ('_p25e_{0}.cer' -f $tag)
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  W ("  --- certutil -dump {0} (ground truth) ---" -f $tag)
  (& certutil -dump $cer 2>&1) | Where-Object { $_ -match 'Basic Constraints|Key Usage|cA=|CA=|Subject|Issuer|critical|KeyCert|Digit' } |
    Select-Object -First 14 | ForEach-Object { W ('    ' + $_.Trim()) }
}
W ("signtool = {0}" -f $signtool)
W '--- 0a: reference - signer chain of an ALREADY-LOADED kernel driver (gdrv3.sys) ---'
$ref = Get-AuthenticodeSignature 'C:\Windows\System32\drivers\gdrv3.sys'
if($ref -and $ref.SignerCertificate){
  W ("  status={0} signer={1}" -f $ref.Status,$ref.SignerCertificate.Subject)
  $ch = $null; [void][System.Security.Cryptography.X509Certificates.X509Chain]::new().Build($ref.SignerCertificate,[ref]$ch)
  if($ch){ $i=0; foreach($el in $ch.ChainElements){ W ("    [el{0}] {1}" -f $i,$el.Certificate.Subject); W ("           {0}" -f (Sig-Info $el.Certificate)); $i++ } }
} else { W '  gdrv3.sys not present/unsigned - no reference' }
W ''


########## 1: inventory with FIXED decoders + certutil ground truth ##########
W "########## 1: inventory of ApexDrv certs (fixed decoder + certutil truth) ##########"
$all = @()
foreach($st in 'My','Root','TrustedPublisher'){
  W ("  --- Cert:\LocalMachine\{0} ---" -f $st)
  foreach($c in @(Get-ChildItem -LiteralPath ("Cert:\LocalMachine\{0}" -f $st))){
    $s = Sig-Info $c
    W ("    {0}  {1}" -f $c.Thumbprint,$c.Subject)
    W ("       {0}" -f $s)
    $all += [pscustomobject]@{ Thumb=$c.Thumbprint; Subject=$c.Subject; Store=$st; Info=$s; Cert=$c }
  }
}
$cand = @($all | Where-Object { $_.Store -eq 'My' -and $_.Info -match 'certSign=True' -and $_.Info -match 'BC=True' } |
        Sort-Object Subject -Unique)
W ("  signer candidates (My + keyCertSign + BC cA=TRUE) = {0}" -f $cand.Count)
foreach($x in $cand){ W ("    CAND {0}  {1}  [{2}]" -f $x.Thumb,$x.Subject,$x.Info) }
W ''
W '  --- certutil ground truth on the interesting certs ---'
foreach($x in @($all | Where-Object { $_.Store -eq 'My' } | Sort-Object Subject -Unique)){
  if($x.Info -match 'certSign=True'){ Certutil-Dump $x.Cert ($x.Thumb.Substring(0,8)) }
}
W ''


########## 2: shape harness ##########
$sig = $signtool
function Trust-Root($c){
  $cer = Join-Path $PSScriptRoot ('_p25e_root_{0}.cer' -f $c.Thumbprint.Substring(0,8))
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
  return $cer
}
function Trust-Pub($c){
  $cer = Join-Path $PSScriptRoot ('_p25e_pub_{0}.cer' -f $c.Thumbprint.Substring(0,8))
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
  return $cer
}
function Keep-Useful($txt){
  @(($txt -split "`n") | Where-Object { $_ -match 'Issued to|Issued by|Error|error|SignTool|Successfully|Chain|Signature|Version of|Hash of|0x8|verified|Serial|Digest|The signature|The certificate' }) |
    ForEach-Object { '      ' + $_.Trim() } | Select-Object -First 30
}
function Sign-Verify($c,$tag){
  $f = Join-Path $PSScriptRoot ('_p25e_{0}.sys' -f $tag)
  Copy-Item -LiteralPath $sys -Destination $f -Force
  $s  = ((& $sig sign /v /sm /sha1 $c.Thumbprint /fd SHA256 $f 2>&1) -join "`n")
  $se = if($s -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $v  = ((& $sig verify /v /kp $f 2>&1) -join "`n")
  $er = if($v -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  W ("      sign_errors={0}  verify /kp errors={1}" -f $se,$er)
  Keep-Useful $v | ForEach-Object { W $_ }
  $codes = @(($v -split "`n") | Where-Object { $_ -match '0x8[0-9A-Fa-f]{7}' } | ForEach-Object { ($_ -replace '.*?(0x8[0-9A-Fa-f]{7}).*','$1').Trim() } | Select-Object -Unique)
  if($codes){ W ('      error codes: ' + ($codes -join ', ')) }
  return @{ se=$se; er=$er; file=$f; tag=$tag; cert=$c; codes=($codes -join ',') }
}
function New-Cert($sub,$ca,$eku,$kuList,$signer){
  $p = @{ CertStoreLocation='Cert:\LocalMachine\My'; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048
          HashAlgorithm='SHA256'; Subject=$sub; NotAfter=$(if($ca){(Get-Date).AddYears(10)}else{(Get-Date).AddYears(5)}); Type='Custom' }
  $te = @()
  if($null -ne $ca){ $te += ('2.5.29.19={critical}{text}ca=' + $(if($ca){'1'}else{'0'})) }
  if($eku){ $te += '2.5.29.37={text}1.3.6.1.5.5.7.3.3' }
  if($te.Count){ $p.TextExtension = $te }
  if($kuList){ $p.KeyUsage = $kuList }
  if($signer){ $p.Signer = $signer }
  return (New-SelfSignedCertificate @p)
}
$script:results = @()
function Try-Shape($tag,$cert,$trustRoot,$trustPub,$note){
  W ("  --- shape {0}: {1}" -f $tag,$note)
  if(-not $cert){
    W '      CREATE FAILED (New-SelfSignedCertificate returned nothing) - see errors above'
    $script:results += [pscustomobject]@{ Tag=$tag; Er=-2; Se=-2; Thumb=''; Subject='(create failed)'; Codes=''; File='' }
    W ''
    return @{ er=-2; se=-2; codes=''; file='' }
  }
  W ("      thumb={0} {1}" -f $cert.Thumbprint,$cert.Subject)
  W ("      actual: {0}" -f (Sig-Info $cert))
  Certutil-Dump $cert $tag
  $rc = Trust-Root $cert
  if($trustPub){ $rp = Trust-Pub $cert }
  $r = Sign-Verify $cert $tag
  $script:results += [pscustomobject]@{ Tag=$tag; Er=$r.er; Se=$r.se; Thumb=$cert.Thumbprint; Subject=$cert.Subject; Codes=$r.codes; File=$r.file }
  if($r.er -ne 0 -and -not $trustPub){
    W '      (retry with the SIGNER also trusted in TrustedPublisher)'
    $r2 = Sign-Verify $cert ($tag + 'tp')
    $script:results += [pscustomobject]@{ Tag=($tag+'tp'); Er=$r2.er; Se=$r2.se; Thumb=$cert.Thumbprint; Subject=$cert.Subject; Codes=$r2.codes; File=$r2.file }
  }
  W ''
  return $r
}

########## 3: build + test the shapes ##########
W "########## 3: shapes (S1 self-signed CA | S2 proper root+leaf | S3 leaf w/o BC | S4 leaf ca=1 | S5 self-signed CA, no EKU) ##########"
$win = $null; $winTag = $null
$kuCa = @('DigitalSignature','CertSign','CRLSign')

$s1 = New-Cert 'CN=ApexDrv S1 SelfSigned CA (QwenKern)' $true $true $kuCa $null
$r1 = Try-Shape 'S1' $s1 $true $true 'self-signed CA, BC ca=1 crit, KU digitalSignature|keyCertSign|cRLSign, EKU codesign'
if($r1.se -eq 0 -and $r1.er -eq 0 -and -not $win){ $win=$s1; $winTag='S1' }

$s2root = New-Cert 'CN=ApexDrv S2 Root CA (QwenKern)' $true $false @('CertSign','CRLSign') $null
Certutil-Dump $s2root 'S2root'
$s2leaf = New-Cert 'CN=ApexDrv S2 Leaf (QwenKern)' $false $true @('DigitalSignature') $s2root
$r2 = Try-Shape 'S2' $s2leaf $true $false 'root(ca=1 crit,KU CertSign) -> leaf(ca=0 crit,KU digitalSignature,EKU codesign); leaf NOT in TrustedPublisher'
if($r2.se -eq 0 -and $r2.er -eq 0 -and -not $win){ $win=$s2leaf; $winTag='S2' }

$s3leaf = New-Cert 'CN=ApexDrv S3 LeafNoBC (QwenKern)' $null $true @('DigitalSignature') $s2root
$r3 = Try-Shape 'S3' $s3leaf $true $false 'leaf with NO basicConstraints extension at all'
if($r3.se -eq 0 -and $r3.er -eq 0 -and -not $win){ $win=$s3leaf; $winTag='S3' }

$s4leaf = New-Cert 'CN=ApexDrv S4 LeafCA (QwenKern)' $true $true @('DigitalSignature') $s2root
$r4 = Try-Shape 'S4' $s4leaf $true $false 'leaf with BC ca=1 (makecert-style)'
if($r4.se -eq 0 -and $r4.er -eq 0 -and -not $win){ $win=$s4leaf; $winTag='S4' }

$s5 = New-Cert 'CN=ApexDrv S5 SelfSigned NoEKU (QwenKern)' $true $false $kuCa $null
$r5 = Try-Shape 'S5' $s5 $true $true 'self-signed CA, BC ca=1 crit, KU certSign, NO EKU'
if($r5.se -eq 0 -and $r5.er -eq 0 -and -not $win){ $win=$s5; $winTag='S5' }

W "########## 3b: shape scoreboard ##########"
foreach($x in $script:results){ W ("  {0,-6} sign_errors={1,-3} kp_errors={2,-3} codes=[{3}] {4}" -f $x.Tag,$x.Se,$x.Er,$x.Codes,$x.Subject) }
W ''


########## 3c: legacy candidate sweep (are the already-trusted c2/c3 any better?) ##########
W "########## 3c: legacy candidates already in My with certSign + BC cA=TRUE ##########"
$legacy = @(Get-ChildItem Cert:\LocalMachine\My | Where-Object { (CertSign $_) -and (CaOf $_) -eq 'True' })
if(-not $legacy){ W '  none' }
foreach($c in $legacy){
  W ("  legacy {0} {1}" -f $c.Thumbprint,$c.Subject)
  W ("      actual: {0}" -f (Sig-Info $c))
  $r = Sign-Verify $c ('L' + $c.Thumbprint.Substring(0,6))
  $script:results += [pscustomobject]@{ Tag=('L'+$c.Thumbprint.Substring(0,6)); Er=$r.er; Se=$r.se; Thumb=$c.Thumbprint; Subject=$c.Subject; Codes=$r.codes; File=$r.file }
  if($r.se -eq 0 -and $r.er -eq 0 -and -not $win){ $win=$c; $winTag=('legacy:'+$c.Thumbprint) }
}
W ''

########## 4: sign the REAL driver with the winner + service test ##########
W "########## 4: real driver ##########"
if($win){
  W ("  WINNER: tag={0} thumb={1}" -f $winTag,$win.Thumbprint)
  W ("          {0}" -f $win.Subject)
  $bak = 'C:\Windows\System32\drivers\apexdrv.sys.bak_p25e'
  if(-not (Test-Path -LiteralPath $bak)){ Copy-Item -LiteralPath $sys -Destination $bak -Force; W ("  pristine backup -> {0}" -f $bak) }
  else { W ("  backup already present -> {0}" -f $bak) }
  $sp = ((& $sig sign /v /sm /sha1 $win.Thumbprint /fd SHA256 $sys 2>&1) -join "`n")
  W ("  real sign: {0}" -f (($sp -split "`n") | Where-Object { $_ -match 'Successfully signed|Number of errors' } | ForEach-Object { $_.Trim() } | Select-Object -First 2 | ForEach-Object { $_ }))
  $v = ((& $sig verify /v /kp $sys 2>&1) -join "`n")
  $ver = if($v -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  W ("  real verify /kp errors = {0}" -f $ver)
  Keep-Useful $v | ForEach-Object { W $_ }
  W ("  Get-AuthenticodeSignature = {0}" -f (Get-AuthenticodeSignature $sys).Status)
  $stage = 'C:\ProgramData\QwenKern\apexdrv.sys'
  Copy-Item -LiteralPath $sys -Destination $stage -Force
  W ("  restage: {0} exists={1} size={2}" -f $stage,(Test-Path -LiteralPath $stage),(Get-Item -LiteralPath $stage).Length)
  $sysQ = '"' + $sys + '"'
  W ("  stop   : {0}" -f (((& sc.exe stop kernprobe 2>&1) -join ' ') -replace '\s+',' '))
  W ("  delete : {0}" -f (((& sc.exe delete kernprobe 2>&1) -join ' ') -replace '\s+',' '))
  Start-Sleep -Milliseconds 500
  W ("  create : {0}" -f (((& sc.exe create kernprobe type= kernel start= demand binPath= $sysQ DisplayName= 'ApexDrv kernprobe (p25e)' 2>&1) -join ' ') -replace '\s+',' '))
  W ("  start  : {0}" -f (((& sc.exe start kernprobe 2>&1) -join ' ') -replace '\s+',' '))
  Start-Sleep -Milliseconds 900
  $q = (((& sc.exe query kernprobe 2>&1) -join ' ') -replace '\s+',' ')
  W ("  query  : {0}" -f $q)
} else {
  W '  NO WINNER - real driver untouched (it still carries the p25c/p25d signature).'
}
W ''

########## 5: verdict ##########
W "########## 5: VERDICT / NEXT ##########"
$zero = @($script:results | Where-Object { $_.Er -eq 0 })
$run  = ($q -match 'RUNNING')
if($win){
  W ("  PASS - {0} verified under kernel policy (/kp errors=0)." -f $winTag)
  W ("  signer thumbprint = {0}" -f $win.Thumbprint)
  W ("  kernprobe RUNNING under DSE (testsigning OFF) = {0}" -f $run)
  W ("  -> point the build/index at this signer, keep testsigning OFF, re-verify Apex + EAAC.")
  ("thumb={0}`r`nsubject={1}`r`nshape={2}`r`nwhen={3}" -f $win.Thumbprint,$win.Subject,$winTag,(Get-Date)) | Set-Content -LiteralPath (Join-Path $PSScriptRoot '_p25e_winner.txt')
} else {
  W '  STILL BLOCKED - no shape passed /kp. Read the per-shape error codes above:'
  W '    if every shape repeats 0x80096019 -> AK is refusing the local root itself, so the only'
  W '       local route left is testsigning on.'
  W '    if codes differ per shape -> the shape is the lever; iterate on the one closest to 0.'
  W '  -> fork: (A) keep gdrv3 transport (zero risk), (B) bcdedit /set testsigning on + reboot.'
}
W '-- CI events (last 30 min):'
try {
  Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddMinutes(-30) } -ErrorAction Stop |
    Where-Object { $_.Id -in 3004,3033,3077,3089 } | Select-Object -First 12 |
    ForEach-Object { $m = ($_.Message -replace '\s+',' '); W ("    {0} id={1} {2}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,$m.Substring(0,[Math]::Min(150,$m.Length))) }
} catch { W ("  (CodeIntegrity log read failed: {0})" -f $_.Exception.Message) }
W '-- ROLLBACK driver: Copy-Item -LiteralPath "C:\Windows\System32\drivers\apexdrv.sys.bak_p25e" -Destination "C:\Windows\System32\drivers\apexdrv.sys" -Force ; sc stop kernprobe ; sc delete kernprobe'
W "-- ROLLBACK certs : Get-ChildItem Cert:\LocalMachine\My | ?{`$_.Subject -match 'ApexDrv S[1-5]'} | Remove-Item"
W ("=== p25e END {0} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
L ("p25e END winner={0} shapes={1} zero={2}" -f $winTag,$script:results.Count,$zero.Count)
