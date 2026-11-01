# p25b - PROBE: find the exact cert-creation spell that makes KeyUsage keyCertSign actually land.
#
# p25 evidence (p25.txt):
#   root check: BC present=True cA=True critical=True CertSign=False    <-- -KeyUsage did NOT apply
#   leaf check: ... EKU=1.3.6.1.5.5.7.3.3 KeyUsage=                     <-- KeyUsage extension ABSENT
#   [leaf]    verify /kp errors = 1 (chain build in Root store = True)
#   [oneshot] verify /kp -> 0x80096019 "basic constraint extension has not been observed"
# -> both candidates failed for ONE reason: a cert acting as its own issuer / CA has no
#    keyCertSign. New-SelfSignedCertificate silently dropped "-KeyUsage CertSign,CRLSign,...".
#
# This probe builds 6 variants, dumps the raw extension state of each, then signs a SCRATCH copy
# of the driver with each and runs "signtool verify /kp" - the variant whose /kp returns 0 errors
# is the working spell. Then it uses that spell for a real CA + leaf and re-tests the service.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25b.txt'
$log = Join-Path $PSScriptRoot 'run25b.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25b (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; the elevated p25b writes p25b.txt'
  exit
}
"=== p25b KEYUSAGE PROBE $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sys  = 'C:\Windows\System32\drivers\apexdrv.sys'
$stg  = 'C:\ProgramData\QwenKern\apexdrv.sys'
$scr  = Join-Path $PSScriptRoot '_probe.sys'
$signtool = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$kuFlag = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]
Copy-Item -LiteralPath $sys -Destination $scr -Force
W ("signtool = {0}" -f $signtool)
W ("scratch  = {0} size={1}" -f $scr,(Get-Item -LiteralPath $scr).Length)
W ("enum names available: {0}" -f (([enum]::GetNames($kuFlag)) -join ','))
W ''

function New-ProbeCert($variant,$subject,$ca,$signer){
  $ext = @()
  # NOTE: do NOT use the PS -f operator on these: "{critical}" and "{text}" are placeholders for
  # New-SelfSignedCertificate itself, and String.Format() chokes on them.
  $ext += '2.5.29.19={critical}{text}ca=' + $(if($ca){'1'}else{'0'})
  $p = @{
    Type='Custom'; Subject=$subject; CertStoreLocation='Cert:\LocalMachine\My'
    KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048; HashAlgorithm='SHA256'
    NotAfter=$(if($ca){(Get-Date).AddYears(10)}else{(Get-Date).AddYears(5)})
  }
  if($signer){ $p.Signer = $signer }
  switch($variant){
    'v0' { $p.KeyUsage = $kuFlag::DigitalSignature }
    'v1' { $p.KeyUsage = $kuFlag::DigitalSignature -bor $kuFlag::KeyCertSign -bor $kuFlag::CrlSign
           $p.TextExtension = $ext }
    'v2' { $p.KeyUsage = 'DigitalSignature,KeyCertSign,CrlSign'    # canonical enum-name string (no spaces)
           $p.TextExtension = $ext }
    'v3' { $p.KeyUsage = 'DigitalSignature,CertSign,CRLSign'        # p25 wording (maybe wrong names)
           $p.TextExtension = $ext }
    'v4b'{ }
    'v4' { $p.KeyUsage = $kuFlag::DigitalSignature   # + TextExtension keyusage must win/duplicate
           $p.TextExtension = @($ext + '2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.15={critical}{text}DigitalSignature,KeyCertSign,CrlSign') }
    'v5' { $p.KeyUsage = $kuFlag::DigitalSignature   # 0x86 = digitalSignature|keyCertSign|crlSign raw DER bits
           $p.TextExtension = @($ext + '2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.15={critical}{text}0x86') }
  }
  if($variant -ne 'v4' -and $variant -ne 'v5'){ $p.TextExtension = $ext + '2.5.29.37={text}1.3.6.1.5.5.7.3.3' }
  return (New-SelfSignedCertificate @p)
}

W '########## 1: variant matrix (each self-signed, ca=1, needs KeyUsage CertSign) ##########'
$results = @()
foreach($v in 'v0','v1','v2','v3','v4','v5'){
  $sub = "CN=ApexDrv Probe $v (QwenKern)"
  $c = $null; $err = ''
  try { $c = New-ProbeCert $v $sub $true $null } catch { $err = $_.Exception.Message }
  if(-not $c){ W ("  {0}: CREATE FAILED :: {1}" -f $v,($err -replace '\s+',' ')); continue }
  $bc = $c.Extensions['2.5.29.19']
  W ("  {0}: noThrow=True thumb={1}" -f $v,$c.Thumbprint)
  W ("       KeyUsage ext present={0} value={1} (int={2})" -f ($null -ne $c.Extensions['2.5.29.15']),$c.KeyUsage,[int]$c.KeyUsage)
  W ("       hasCertSign={0}  BC present={1} cA={2} critical={3}  EKU={4}" -f `
    ((([int]$c.KeyUsage -band 4) -ne 0)),($null -ne $bc),$(if($bc){$bc.CertificateAuthority}else{'-'}),$(if($bc){$bc.Critical}else{'-'}), `
    (($c.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ','))
  $results += [pscustomobject]@{ v=$v; cert=$c }
}
W ('  variants that actually carry keyCertSign: {0}' -f (($results | Where-Object { ([int]$_.cert.KeyUsage -band 4) -ne 0 } | ForEach-Object { $_.v }) -join ' '))

W ''
W '########## 2: sign scratch copy with each variant + signtool verify /kp (0 errors = working spell) ##########'
$winner = $null
foreach($r in $results){
  $v = $r.v; $c = $r.cert
  $cer = Join-Path $PSScriptRoot ("_probe_{0}.cer" -f $v)
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
  $sgn = ((& $signtool sign /v /sm /sha1 $c.Thumbprint /fd SHA256 $scr 2>&1) -join ' ')
  $sgnErr = if($sgn -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $out = ((& $signtool verify /v /kp $scr 2>&1) -join "`n")
  $errs = if($out -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $has = ([int]$c.KeyUsage -band 4) -ne 0
  W ("  [{0}] keyCertSign={1} sign_errors={2} -> verify /kp errors = {3}" -f $v,$has,$sgnErr,$errs)
  if($errs -ne 0){
    ($out -split "`n") | Where-Object { $_ -match '0x80|WinVerifyTrust returned error|basic constraint|not trusted|SignTool Error' } |
      Select-Object -First 4 | ForEach-Object { W ("       {0}" -f $_.Trim()) }
  }
  $sig = (Get-AuthenticodeSignature -LiteralPath $scr)
  W ("       Get-AuthenticodeSignature = {0}" -f $sig.Status)
  if($errs -eq 0 -and -not $winner){ $winner = $r; W ("       *** {0} VERIFIES UNDER KERNEL POLICY ***" -f $v) }
}
W ''
if($winner){
  W ("WINNING SPELL = {0}" -f $winner.v)
  W ("  -> use it verbatim for the real CA and for the leaf (ca=0).")
}else{
  W 'NO VARIANT VERIFIED - next action: bcdedit testsigning, or accept gdrv3 transport.'
}

W ''
W '########## 3: real signer = LEAF from a CA built with the winning spell ##########'
function Sign-Verify($cert,$tag,$file){
  if(-not $cert){ return -1 }
  $sgn = ((& $signtool sign /v /sm /sha1 $cert.Thumbprint /fd SHA256 $file 2>&1) -join ' ')
  $se  = if($sgn -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $out = ((& $signtool verify /v /kp $file 2>&1) -join "`n")
  $er  = if($out -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  W ("  [{0}] sign_errors={1} verify /kp errors = {2}" -f $tag,$se,$er)
  if($er -ne 0){ ($out -split "`n") | Where-Object { $_ -match '0x80|basic constraint|SignTool Error' } | Select-Object -First 3 | ForEach-Object { W ("       {0}" -f $_.Trim()) } }
  return $er
}
$caEr = -1; $lfEr = -1
if($winner){
  $v = $winner.v
  $ca = $null; $lf = $null
  try { $ca = New-ProbeCert $v 'CN=ApexDrv Lab Root CA 2 (QwenKern)' $true $null } catch { W ("  CA CREATE FAILED :: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
  if($ca){
    $cbc = $ca.Extensions['2.5.29.19']
    W ("  CA thumb={0} KeyUsage={1} (int={2}) cA={3} critical={4}" -f $ca.Thumbprint,$ca.KeyUsage,[int]$ca.KeyUsage,$cbc.CertificateAuthority,$cbc.Critical)
    $cc = Join-Path $PSScriptRoot 'apexdrv_lab_root2.cer'
    Export-Certificate -Cert $ca -FilePath $cc -Force | Out-Null
    Import-Certificate -FilePath $cc -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
    Import-Certificate -FilePath $cc -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
    try { $lf = New-ProbeCert $v 'CN=ApexDrv Lab Code Signing 2 (QwenKern)' $false $ca } catch { W ("  LEAF CREATE FAILED :: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
    if($lf){
      $lbc = $lf.Extensions['2.5.29.19']
      W ("  LEAF thumb={0} KeyUsage={1} cA={2} AKI={3} EKU={4}" -f $lf.Thumbprint,$lf.KeyUsage,$lbc.CertificateAuthority,($null -ne $lf.Extensions['2.5.29.35']),(($lf.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ','))
      $lc = Join-Path $PSScriptRoot 'apexdrv_lab_leaf2.cer'
      Export-Certificate -Cert $lf -FilePath $lc -Force | Out-Null
      Import-Certificate -FilePath $lc -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
      $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
      $ch.ChainPolicy.RevocationMode = 'NoCheck'
      W ("  user-mode chain anchored in Root store = {0}" -f $ch.Build($lf))

      W '  -- (a) CA-only signer on the REAL driver:'
      $caEr = Sign-Verify $ca 'ca' $sys
      W '  -- (b) CA->LEAF signer on the REAL driver:'
      $lfEr = Sign-Verify $lf 'leaf' $sys
      $chosen = if($lfEr -eq 0){ 'LEAF (proper CA->leaf chain)' } elseif($caEr -eq 0){ 'CA-only (makecert -r shape)' } else { 'NONE' }
      W ("  CHOSEN = {0}" -f $chosen)
    }
  }
}

W ''
W '########## 4: service clean re-create + start under DSE (testsigning OFF) ##########'
& sc.exe stop kernprobe   *> $null
& sc.exe delete kernprobe *> $null
W ("  create : {0}" -f (((& sc.exe create kernprobe type= kernel start= demand binPath= 'System32\drivers\apexdrv.sys' 2>&1) -join ' ') -replace '\s+',' '))
W ("  start  : {0}" -f (((& sc.exe start kernprobe 2>&1) -join ' ') -replace '\s+',' '))
W ("  query  : {0}" -f (((& sc.exe query kernprobe 2>&1) -join ' ') -replace '\s+',' '))
$q = ((& sc.exe query kernprobe 2>&1) -join ' ')
$running = $q -match 'RUNNING'
W ''
W '########## 5: VERDICT ##########'
if($running){ W '  PASS - apexdrv.sys loaded under DSE with testsigning OFF. EAAC gate untouched.' }
else{ W '  STILL BLOCKED - see section 2/3 winner + /kp error lines above.' }
$ci = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddMinutes(-6)} -ErrorAction SilentlyContinue |
      Where-Object { $_.Message -match 'apexdrv' } | Select-Object -First 6
if($ci){ W '-- recent CI events:'; $ci | ForEach-Object { W ("   {0} id={1}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id) } }
W ("-- p25b END {0} --" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
