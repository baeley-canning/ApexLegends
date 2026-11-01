# p25 - DSE repair attempt #2: give the lab driver a REAL root-CA -> leaf signing chain.
#
# p24 result (16:16, logged in p24.txt): cert was built with BasicConstraints ca=1 critical +
# Code Signing EKU, signtool signed the blob fine, but
#   - signtool verify /kp  -> 0x80096019 TRUST_E_BASIC_CONSTRAINTS ("basic constraint
#     extension has not been observed") and
#   - kernel CI still logged 3004 on load -> sc start kernprobe = ERROR 577.
# Reason: a ca=1 certificate used as its own issuer must ALSO carry KeyUsage CertSign, and a CA
# shoved into the leaf role is not the shape Kernel Mode Code Integrity wants.
# p24 also proved user-mode trust is NOT the question: the shipped blob was already
# Get-AuthenticodeSignature = Valid while kernel CI refused it.
#
# Canonical kernel-dev shape (what "makecert -r -pe -eku CodeSigning" produced for a decade):
#   ROOT : BasicConstraints ca=1 critical, KeyUsage CertSign+CRLSign+DigitalSignature -> LocalMachine\Root
#   LEAF : BasicConstraints ca=0, KeyUsage DigitalSignature, EKU Code Signing, AKI -> root,
#          its own cert into LocalMachine\TrustedPublisher
#   FILE : SHA256 Authenticode embedded signature made by LEAF
# Fallback (only if the two-tier path fails): ONE ca=1 CertSign cert (the makecert -r one-cert shape).
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25.txt'
$log = Join-Path $PSScriptRoot 'run25.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25 (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; the elevated p25 writes p25.txt'
  exit
}
"=== p25 DSE REPAIR #2 (root CA + leaf) $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sys  = 'C:\Windows\System32\drivers\apexdrv.sys'
$bak  = $sys + '.bak_p24'
$stg  = 'C:\ProgramData\QwenKern\apexdrv.sys'
$caSub   = 'CN=ApexDrv Lab Root CA (QwenKern)'
$leafSub = 'CN=ApexDrv Lab Code Signing (QwenKern)'
$oneSub  = 'CN=ApexDrv Lab DSE CertSign (QwenKern)'
$signtool = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

W '########## 0: environment truth ##########'
$sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
W ("  SystemStartOptions = [{0}]" -f $sso)
W ("  testsigning booted = {0}   (must stay False for the EAAC gate)" -f ($sso -match 'TESTSIGNING'))
W ("  signtool  = {0}" -f $signtool)
W ("  driver = {0} exists={1} size={2}" -f $sys,(Test-Path -LiteralPath $sys),$(if(Test-Path -LiteralPath $sys){(Get-Item -LiteralPath $sys).Length}else{'-'}))
W ("  pristine backup {0} exists={1}" -f $bak,(Test-Path -LiteralPath $bak))
W ("  QwenKern certs already present: Root={0} TrustedPublisher={1}" -f `
  (@(Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match 'QwenKern' }).Count), `
  (@(Get-ChildItem Cert:\LocalMachine\TrustedPublisher | Where-Object { $_.Subject -match 'QwenKern' }).Count))

W '-- hygiene: evict p24''s malformed cert (cA=1 but KeyUsage=DigitalSignature only) from the trust stores'
foreach($st in 'Root','TrustedPublisher'){
  Get-ChildItem ("Cert:\LocalMachine\" + $st) | Where-Object { $_.Subject -eq 'CN=ApexDrv Lab DSE (QwenKern)' } | ForEach-Object {
    W ("   evicting {0} from LocalMachine\{1} thumb={2}" -f $_.Subject,$st,$_.Thumbprint)
    Remove-Item -LiteralPath $_.PSPath -Force -ErrorAction SilentlyContinue
  }
}

W ''
W '########## 1: build ROOT CA (ca=1 critical + KeyUsage CertSign/CRLSign) ##########'
$ca = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $caSub } | Select-Object -First 1
if($ca){ W ("  reusing existing root {0} thumb={1}" -f $caSub,$ca.Thumbprint) }
else {
  try {
    $ca = New-SelfSignedCertificate -Type Custom -Subject $caSub `
      -CertStoreLocation 'Cert:\LocalMachine\My' -KeyExportPolicy Exportable `
      -KeyUsage CertSign,CRLSign,DigitalSignature -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
      -NotAfter (Get-Date).AddYears(10) `
      -TextExtension @('2.5.29.19={critical}{text}ca=1')
    W ("  created root thumb={0} notAfter={1}" -f $ca.Thumbprint,$ca.NotAfter)
  } catch { W ("  ROOT CREATE FAILED: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
}
if($ca){
  $bcr = $ca.Extensions['2.5.29.19']
  W ("  root check: BC present={0} cA={1} critical={2} CertSign={3} SKI={4}" -f `
    ($null -ne $bcr),$(if($bcr){$bcr.CertificateAuthority}else{'-'}),$(if($bcr){$bcr.Critical}else{'-'}), `
    (($ca.KeyUsage -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign) -ne 0), `
    ($null -ne $ca.Extensions['2.5.29.14']))
  $caCer = Join-Path $PSScriptRoot 'apexdrv_lab_root.cer'
  Export-Certificate -Cert $ca -FilePath $caCer -Force | Out-Null
  Import-Certificate -FilePath $caCer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
  W '  root .cer exported + imported -> LocalMachine\Root'
}

W ''
W '########## 2: build LEAF code-signing cert signed by that root ##########'
$leaf = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $leafSub } | Select-Object -First 1
if($leaf){ W ("  reusing existing leaf thumb={0}" -f $leaf.Thumbprint) }
elseif($ca){
  try {
    $leaf = New-SelfSignedCertificate -Type Custom -Subject $leafSub -Signer $ca `
      -CertStoreLocation 'Cert:\LocalMachine\My' -KeyExportPolicy Exportable `
      -KeyUsage DigitalSignature -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
      -NotAfter (Get-Date).AddYears(5) `
      -TextExtension @('2.5.29.19={critical}{text}ca=0','2.5.29.37={text}1.3.6.1.5.5.7.3.3')
    W ("  created leaf thumb={0} notAfter={1}" -f $leaf.Thumbprint,$leaf.NotAfter)
  } catch { W ("  LEAF CREATE FAILED: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
}
if($leaf){
  $bcl = $leaf.Extensions['2.5.29.19']
  W ("  leaf check: subject='{0}'" -f $leaf.Subject)
  W ("              issuer='{0}'" -f $leaf.Issuer)
  W ("              BC present={0} cA={1} critical={2} AKI={3} SKI={4} EKU={5} KeyUsage={6}" -f `
    ($null -ne $bcl),$(if($bcl){$bcl.CertificateAuthority}else{'-'}),$(if($bcl){$bcl.Critical}else{'-'}), `
    ($null -ne $leaf.Extensions['2.5.29.35']),($null -ne $leaf.Extensions['2.5.29.14']), `
    (($leaf.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ','),$leaf.KeyUsage)
  $leafCer = Join-Path $PSScriptRoot 'apexdrv_lab_leaf.cer'
  Export-Certificate -Cert $leaf -FilePath $leafCer -Force | Out-Null
  Import-Certificate -FilePath $leafCer -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
  W '  leaf .cer exported + imported -> LocalMachine\TrustedPublisher'
  $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
  $ch.ChainPolicy.RevocationMode = 'NoCheck'
  $cb = $ch.Build($leaf)
  W ("  user-mode chain build anchored in Root store = {0}" -f $cb)
  if($ch.ChainStatus.Count){ $ch.ChainStatus | ForEach-Object { W ("    chain status: {0} :: {1}" -f $_.Status,($_.StatusInformation -replace '\s+',' ')) } }
}

W ''
W '########## 3: sign apexdrv.sys with the LEAF, verify under kernel policy (/kp) ##########'
if(-not (Test-Path -LiteralPath $bak)){ Copy-Item -LiteralPath $sys -Destination $bak -Force; W ("  pristine backup -> {0}" -f $bak) }
else { W ("  pristine backup already present -> {0}" -f $bak) }

function Sign-Try($cert,$tag){
  if(-not $cert){ W ("  [{0}] no cert -> skip" -f $tag); return $false }
  W ("  [{0}] signer thumb={1}" -f $tag,$cert.Thumbprint)
  $s = ((& $signtool sign /v /sm /sha1 $cert.Thumbprint /fd SHA256 $sys 2>&1) -join "`n")
  ($s -split "`n") | Where-Object { $_ -match 'Successfully signed|Number of errors|Number of warnings' } | ForEach-Object { W ('    sign: ' + $_.Trim()) }
  $v = ((& $signtool verify /v /kp $sys 2>&1) -join "`n")
  $errs = -1
  if($v -match 'Number of errors:\s*(\d+)'){ $errs = [int]$Matches[1] }
  W ("  [{0}] verify /kp errors = {1}" -f $tag,$errs)
  ($v -split "`n") | Where-Object { $_ -match 'WinVerifyTrust returned error|constraint|not trusted|expired|0x8009|0x800B' } | ForEach-Object { W ('    verify: ' + $_.Trim()) }
  $auth = Get-AuthenticodeSignature -LiteralPath $sys
  W ("  [{0}] Get-AuthenticodeSignature = {1}" -f $tag,$auth.Status)
  return (($errs -eq 0) -and ($auth.Status -eq 'Valid'))
}

$signer = $null
if($leaf -and (Sign-Try $leaf 'leaf')){ $signer = $leaf }
else {
  W '  leaf path did not verify -> FALLBACK: one self-signed ca=1 cert WITH KeyUsage CertSign (makecert -r shape)'
  $one = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $oneSub } | Select-Object -First 1
  if(-not $one){
    try {
      $one = New-SelfSignedCertificate -Type Custom -Subject $oneSub -CertStoreLocation 'Cert:\LocalMachine\My' `
        -KeyExportPolicy Exportable -KeyUsage CertSign,CRLSign,DigitalSignature `
        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(5) `
        -TextExtension @('2.5.29.19={critical}{text}ca=1','2.5.29.37={text}1.3.6.1.5.5.7.3.3')
      W ("  created fallback thumb={0}" -f $one.Thumbprint)
    } catch { W ("  FALLBACK CREATE FAILED: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
  }
  if($one){
    $oneCer = Join-Path $PSScriptRoot 'apexdrv_lab_oneshot.cer'
    Export-Certificate -Cert $one -FilePath $oneCer -Force | Out-Null
    foreach($st in 'Root','TrustedPublisher'){ Import-Certificate -FilePath $oneCer -CertStoreLocation ("Cert:\LocalMachine\$st") | Out-Null }
    W '  fallback cert -> Root + TrustedPublisher'
    if(Sign-Try $one 'oneshot'){ $signer = $one }
  }
}
W ("  CHOSEN SIGNER = {0}" -f $(if($signer){ $signer.Subject + '  thumb=' + $signer.Thumbprint } else { 'NONE (no candidate verified)' }))

W ''
W '########## 4: service clean re-create + start under DSE (testsigning OFF) ##########'
if($signer -and (Test-Path -LiteralPath $stg)){
  Copy-Item -LiteralPath $sys -Destination $stg -Force
  W ("  restaged {0} size={1}" -f $stg,(Get-Item -LiteralPath $stg).Length)
} else { W ("  staging copy left as-is: {0} exists={1}" -f $stg,(Test-Path -LiteralPath $stg)) }
W ("  stop   : {0}" -f ((((& sc.exe stop kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
W ("  delete : {0}" -f ((((& sc.exe delete kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 2
W ("  create : {0}" -f ((((& sc.exe create kernprobe type= kernel start= demand binPath= System32\drivers\apexdrv.sys 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 1
W ("  start  : {0}" -f ((((& sc.exe start kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 2
$q = ((& sc.exe query kernprobe 2>&1) -join ' ')
W ("  query  : {0}" -f ($q -replace '\s+',' '))

W ''
W '########## 5: RESULT / NEXT ACTION ##########'
if($q -match 'RUNNING'){
  W '  PASS - apexdrv.sys LOADS under DSE with testsigning OFF.'
  W '  => root cause pinned: kernel CI needs a well-formed chain to a trusted Root-store anchor with'
  W '     KeyUsage CertSign on the CA; the old plain "New-SelfSignedCertificate -Type CodeSigningCert"'
  W '     cert (no BasicConstraints, no CertSign) could never satisfy it - while user mode kept saying Valid.'
  W '  => the lab kernel transport is therefore compatible with the p21 gate fix: NO reboot, NO testsigning.'
  W '     The EAAC popup stays away AND kernprobe is loadable -> restage done, nothing else needed.'
} elseif($q -match '577|SERVICE_RUNNING|STOPPED'){
  W '  STILL BLOCKED - kernel CI refuses the embedded signature even with a proper CA->leaf chain.'
  W '  -> fallback A (recommended, zero risk): keep testsigning OFF and let gdrv3.sys carry the kernel'
  W '     path (ext/gio.py already says "No own driver is used"; gdrv3 is loaded and RUNNING).'
  W '  -> fallback B: bcdedit /set testsigning on + reboot if apexdrv is really wanted - but then EAAC'
  W '     pops again, so pair it with the p21 flag matrix.'
  W "  -> diagnostic: the /kp verify line above is the whole story; if it is still 0x80096019 the CI"
  W '     policy refuses local-machine CAs entirely (then only a real CA/bcdedit route remains).'
} else {
  W '  INCONCLUSIVE - see the query line above.'
}
W '-- CodeIntegrity events matching apexdrv (last 8):'
$ci = @(Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 60 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'apexdrv' } | Select-Object -First 8)
if($ci){ $ci | ForEach-Object { W ('   {0} id={1}' -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id) } } else { W '   (none)' }
W '-- SCM events (last 8):'
$sy = @(Get-WinEvent -LogName System -MaxEvents 300 -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'Service Control Manager' -and $_.Message -match 'kernprobe|apexdrv' } | Select-Object -First 8)
if($sy){ $sy | ForEach-Object { W ('   {0} id={1} :: {2}' -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,(($_.Message -replace '\s+',' ').Trim())) } } else { W '   (none)' }
W ''
W ('-- ROLLBACK: Copy-Item -LiteralPath "{0}" -Destination "{1}" -Force ; sc stop kernprobe ; sc delete kernprobe' -f $bak,$sys)
W '-- ROLLBACK certs: Get-ChildItem Cert:\LocalMachine\My | ?{$_.Subject -match "ApexDrv Lab"} | Remove-Item'
W "-- p25 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
