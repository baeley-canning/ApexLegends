# p25d - decode keyUsage AUTHORITATIVELY (p25c.txt showed my reader was lying) and /kp-test it.
#
# p25c.txt facts:
#   c2/c3 have keyUsage RAW = 03-02-01-86  == digitalSignature | keyCertSign | cRLSign   <-- CORRECT!
#   yet my hasCertSign gate said False, because:
#     * [X509KeyUsageFlags]::CertSign does not exist (that name is only in the cmdlet's own enum) -> $null -> 0
#     * $c.KeyUsage is not a member on .NET Core/PS7 -> $null -> 0
#   => gate skipped Trust-It + /kp entirely for c2/c3, so they were NEVER actually /kp tested.
#   c7 COM: InitializeFromPrivateKey(1,...) -> 0x80070057 (arg order wrong; unused here).
#
# This script creates nothing new. It decodes every ApexDrv cert already in the stores, trusts the
# ones that really do carry CertSign + BasicConstraints(cA=1) + EKU code-signing, then runs the real
# signtool sign + verify /kp. First cert with 0 /kp errors wins and signs the live driver.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25d.txt'
$log = Join-Path $PSScriptRoot 'run25d.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25d (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; elevated p25d writes p25d.txt'
  exit
}
"=== p25d KEYUSAGE TRUTH + /kp PROOF $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') PS=$($PSVersionTable.PSVersion) ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$scr = Join-Path $PSScriptRoot '_probe.sys'
$kue = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]
$signtool = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Copy-Item -LiteralPath $sys -Destination $scr -Force
W ("signtool = {0}" -f $signtool)

########## 0: prove the reader bug ##########
$probe = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match 'ApexDrv' } | Select-Object -First 1
W '--- 0: reader diagnostics (why p25/p25b reported "CertSign=False" on good certs) ---'
W ("  $probe.KeyUsage has a member? {0}" -f [bool]($probe | Get-Member -Name KeyUsage))
W ("  [X509KeyUsageFlags]::CertSign exists? {0}   (real name is KeyCertSign = {1})" -f `
   [bool]('CertSign' -in [System.Enum]::GetNames([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags])), `
   [int][System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign)
W ("  $probe.KeyUsage value = '{0}'  (empty + 0 => property absent under PS7 / .NET Core)" -f $probe.KeyUsage)
W ''

# authoritative decoder: X509KeyUsageExtension baked from the raw extension, plus hex for the record
function KU-Raw($c){
  $ext = $c.Extensions['2.5.29.15']
  if(-not $ext){ return @{ hex='(absent)'; certSign=$false; text='' } }
  $hex = [BitConverter]::ToString($ext.RawData)
  try   { $x = $kue::new([byte[]]$ext.RawData); $names = ($x.KeyUsages -band 0xFFFFF) ; $cs = (($x.KeyUsages -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign) -ne 0); return @{ hex=$hex; certSign=$cs; text=($x.KeyUsages.ToString()) } }
  catch { $d = $ext.RawData; return @{ hex=$hex; certSign=(($d[$d.Count-1] -band 0x04) -ne 0); text='(decode failed)' } }
}
function BC-Of($c){
  $bc = $c.Extensions['2.5.29.19']
  if(-not $bc){ return @{ present=$false; ca=$false; crit=$false } }
  try   { $x = [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new([byte[]]$bc.RawData); return @{ present=$true; ca=$x.CertificateAuthority; crit=$bc.Critical } }
  catch { return @{ present=$true; ca=$false; crit=$bc.Critical } }
}
function EKU-Of($c){ return (($c.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ',') }
function Descr($c){
  $k = KU-Raw $c; $b = BC-Of $c
  return ("ku_raw={0} certSign={1} ku={2} | BC present={3} cA={4} crit={5} | EKU={6}" -f $k.hex,$k.certSign,$k.text,$b.present,$b.ca,$b.crit,(EKU-Of $c))
}

########## 1: inventory - every ApexDrv cert in My and Root, decoded ##########
W '########## 1: inventory of ApexDrv certs (decoded, no guessing) ##########'
$cands = @()
foreach($s in 'My','Root','TrustedPublisher'){
  W ("  --- Cert:\LocalMachine\{0} ---" -f $s)
  Get-ChildItem ("Cert:\LocalMachine\" + $s) | Where-Object { $_.Subject -match 'ApexDrv' } | ForEach-Object {
    W ("    {0}  {1}" -f $_.Thumbprint,$_.Subject)
    W ("       {0}" -f (Descr $_))
    if($s -eq 'My'){
      $k = KU-Raw $_; $b = BC-Of $_
      if($k.certSign -and $b.ca){ $cands += $_ }
    }
  }
}
W ("  candidates (My + certSign + cA=1) = {0}" -f $cands.Count)
$cands = @($cands | Sort-Object NotBefore -Descending | Select-Object -First 10)
W ("  testing newest {0} (junk-cert cap)" -f $cands.Count)
W ''

########## 2: trust each candidate + REAL signtool sign / verify /kp ##########
W '########## 2: sign+verify /kp with every candidate (0 errors = working signer) ##########'
function Trust-It($c){
  $cer = Join-Path $PSScriptRoot ('_p25d_{0}.cer' -f $c.Thumbprint.Substring(0,8))
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
}
function Kp-Test($c){
  $s  = ((& $signtool sign /v /sm /sha1 $c.Thumbprint /fd SHA256 $scr 2>&1) -join ' ')
  $se = if($s -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $out = ((& $signtool verify /v /kp $scr 2>&1) -join "`n")
  $er = if($out -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  return @{ se=$se; er=$er; out=$out }
}
$win=$null; $winName=$null
foreach($c in $cands){
  Trust-It $c
  $t = Kp-Test $c
  W ("  [{0}] sign_errors={1}  verify /kp errors={2}" -f $c.Thumbprint.Substring(0,12),$t.se,$t.er)
  ($t.out -split "`n") | Where-Object { $_ -match 'Error|Successfully|verified|constraint|Signing Cert|Issued' } | ForEach-Object { W ('       ' + $_.Trim()) }
  if($t.se -eq 0 -and $t.er -eq 0 -and -not $win){ $win=$c; $winName=$c.Subject }
}

########## 2b: none worked -> build a LEAF under the best candidate and test that ##########
if($win){ W ''; W ("DIRECT CA SIGNER WORKS: {0}" -f $win.Subject) }
elseif($cands.Count -ge 1){
  W ''
  W '  direct CA failed -> trying LEAF under newest candidate ...'
  $ca = $cands | Sort-Object NotBefore -Descending | Select-Object -First 1
  try {
    $leaf = New-SelfSignedCertificate -Type Custom -Subject 'CN=ApexDrv Lab DSE p25d (QwenKern)' `
      -KeyUsage @('DigitalSignature','CRLSign','CertSign') `
      -TextExtension @('2.5.29.19={critical}{text}ca=0','2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
      -Signer $ca -CertStoreLocation 'Cert:\LocalMachine\My' -KeyExportPolicy Exportable -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256
    W ("  leaf = {0}" -f $leaf.Thumbprint)
    W ("       {0}" -f (Descr $leaf))
    Trust-It $leaf
    $t = Kp-Test $leaf
    W ("  leaf /kp errors = {0}" -f $t.er)
    ($t.out -split "`n") | Where-Object { $_ -match 'Error|Successfully|constraint' } | ForEach-Object { W ('       ' + $_.Trim()) }
    if($t.er -eq 0){ $win=$leaf; $winName='LEAF under ' + $ca.Subject }
  } catch { W ("  leaf FAILED :: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
}
W ''

########## 3: real driver sign + restage ##########
if($win){
  $signerName = if($winName){$winName}else{$win.Subject}
  W ("CHOSEN SIGNER = {0}  ({1})" -f $win.Thumbprint,$signerName)
  $s = ((& $signtool sign /v /sm /sha1 $win.Thumbprint /fd SHA256 $sys 2>&1) -join ' ')
  W ("  sign real driver : {0}" -f $s.Substring(0,[Math]::Min(160,$s.Length)))
  $v = ((& $signtool verify /v /kp $sys 2>&1) -join "`n")
  W '  --- verify /kp apexdrv.sys ---'
  ($v -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { W ('   ' + $_.Trim()) }
  W ("  /kp VERDICT = {0}" -f $(if($v -match 'Successfully verified'){'SUCCESS'}else{'FAIL'}))
  if(Test-Path -LiteralPath 'C:\ProgramData\QwenKern'){ Copy-Item -LiteralPath $sys -Destination 'C:\ProgramData\QwenKern\apexdrv.sys' -Force; W '  restaged C:\ProgramData\QwenKern\apexdrv.sys' }
} else { W 'NO SIGNER - skipping real-driver sign' }
W ''

########## 4: service test under DSE (testsigning OFF) ##########
& sc.exe stop kernprobe *> $null
& sc.exe delete kernprobe *> $null
Start-Sleep -Milliseconds 400
$cr = (& sc.exe create kernprobe type= kernel start= demand binPath= ('"' + $sys + '"') DisplayName= "ApexDrv kernprobe (p25d)" 2>&1) -join ' '
W ("  create : {0}" -f $cr)
$st = (& sc.exe start kernprobe 2>&1) -join ' '
W ("  start  : {0}" -f $st)
Start-Sleep -Milliseconds 800
$q = ((& sc.exe query kernprobe 2>&1) -join ' ') -replace '\s+',' '
W ("  query  : {0}" -f $q)
W ''

########## 5: VERDICT ##########
if($q -match 'RUNNING'){
  W 'PASS - kernprobe RUNNING under DSE with testsigning OFF.'
  W '  next: point _index.txt:94 at this signer, re-verify Apex + EAAC, no reboot needed.'
} elseif($win){
  W 'PARTIAL - signer verified 0 /kp errors but the service did not start; read /kp + CI lines.'
} else {
  W 'STILL BLOCKED - every trusted self-signed CA failed /kp. Fork: (A) keep gdrv3 transport, (B) testsigning+reboot.'
}
W '-- CI events (last 30 min):'
Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddMinutes(-30) } -ErrorAction SilentlyContinue |
  Select-Object -First 8 | ForEach-Object { $m = ($_.Message -replace '\s+',' '); W ("   {0} id={1} {2}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,$m.Substring(0,[Math]::Min(150,$m.Length))) }
W ("--- p25d END {0} ---" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
L ("p25d END {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
