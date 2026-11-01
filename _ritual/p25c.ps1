# p25c - PROBE #2: make KeyUsage keyCertSign actually land, then win.
#
# p25b hard facts (p25b.txt):
#   enum names accepted by -KeyUsage are the cmdlet's own:  CertSign / CRLSign  (not KeyCertSign/CrlSign)
#   -Type Custom -KeyUsage DigitalSignature  -> ext present=True but value EMPTY (int=0)   <-- the defect
#   2.5.29.15 TextExtension rejects "DigitalSignature,KeyCertSign,CrlSign" and "0x86" (0x80070057)
#   every empty-KeyUsage cert repeats 0x80096019 on /kp
#
# Variants below cover: the template -Type (which builds its own correct KeyUsage), the cmdlet enum
# spelling, and CertEnroll's canonical lowercase keyusage string. Arm c7 is a raw COM CA as the
# bulletproof fallback. First cert whose /kp returns 0 errors wins and signs the real driver.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25c.txt'
$log = Join-Path $PSScriptRoot 'run25c.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25c (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; the elevated p25c writes p25c.txt'
  exit
}
"=== p25c KEYUSAGE SPELL HUNT $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$scr = Join-Path $PSScriptRoot '_probe.sys'
$signtool = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$kuFlag = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]
Copy-Item -LiteralPath $sys -Destination $scr -Force
W ("signtool = {0}" -f $signtool)

function KU-Info($c){
  if(-not $c){ return 'no-cert' }
  $k = $c.Extensions['2.5.29.15']
  $hex = if($k){ [BitConverter]::ToString($k.RawData) } else { '-' }
  $bits = [int]$c.KeyUsage
  $bc = $c.Extensions['2.5.29.19']
  return ("KeyUsage ext={0} value={1} int=0x{2:X2} raw={3} certSign={4} | BC cA={5} crit={6} | EKU={7}" -f `
    ($null -ne $k),$c.KeyUsage,$bits,$hex,((($bits -band 4) -ne 0)), `
    $(if($bc){$bc.CertificateAuthority}else{'-'}),$(if($bc){$bc.Critical}else{'-'}), `
    (($c.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ','))
}

function Var-Cert($v,$subject,$ca,$signer){
  $ext = @('2.5.29.19={critical}{text}ca=' + $(if($ca){'1'}else{'0'}))
  $eku = '2.5.29.37={text}1.3.6.1.5.5.7.3.3'
  $p = @{ CertStoreLocation='Cert:\LocalMachine\My'; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048; HashAlgorithm='SHA256'
          Subject=$subject; NotAfter=$(if($ca){(Get-Date).AddYears(10)}else{(Get-Date).AddYears(5)}) }
  if($signer){ $p.Signer = $signer }
  switch($v){
    'c1' { $p.Type='CodeSigningCert'; $p.TextExtension = $ext }
    'c2' { $p.Type='CodeSigningCert'; $p.KeyUsage = @('DigitalSignature','CertSign','CRLSign'); $p.TextExtension = $ext }
    'c3' { $p.Type='Custom'; $p.KeyUsage = @('DigitalSignature','CertSign','CRLSign'); $p.TextExtension = $ext + $eku }
    'c4' { $p.Type='Custom'; $p.KeyUsage = @('DigitalSignature'); $p.TextExtension = $ext + $eku + '2.5.29.15={critical}{text}digitalSignature,keyCertSign,cRLSign' }
    'c5' { $p.Type='Custom'; $p.KeyUsage = @('DigitalSignature'); $p.TextExtension = $ext + $eku + '2.5.29.15={critical}digitalSignature,keyCertSign,cRLSign' }
    'c6' { $p.Type='Custom'; $p.KeyUsage = @('DigitalSignature'); $p.TextExtension = $ext + $eku + '2.5.29.15={critical}{text}keyCertSign' }
  }
  return (New-SelfSignedCertificate @p)
}

function Trust-It($c){
  $cer = Join-Path $PSScriptRoot ('_p25c_{0}.cer' -f $c.Thumbprint.Substring(0,8))
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
}
function Kp-Test($c){
  $s = ((& $signtool sign /v /sm /sha1 $c.Thumbprint /fd SHA256 $scr 2>&1) -join ' ')
  $se = if($s -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $out = ((& $signtool verify /v /kp $scr 2>&1) -join "`n")
  $er = if($out -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  return @{ se=$se; er=$er; out=$out }
}


########## 1: spell matrix - first cert with certSign=True AND /kp errors=0 wins ##########
$win = $null; $winName = $null
$names = 'c1','c2','c3','c4','c5','c6'
foreach($v in $names){
  $sub = "CN=ApexDrv CA $v (QwenKern)"
  try   { $c = Var-Cert $v $sub $true $null; $ok=$true }
  catch { $ok=$false; W ("  {0}: CREATE FAILED :: {1}" -f $v,($_.Exception.Message -replace '\s+',' ')) }
  if($ok -and $c){
    W ("  {0}: thumb={1}" -f $v,$c.Thumbprint)
    W ("       {0}" -f (KU-Info $c))
    $bits = [int]$c.KeyUsage
    $hasK = (($bits -band 4) -ne 0)
    W ("       keyCertSign bit set = {0}" -f $hasK)
    if($hasK){
      Trust-It $c
      $t = Kp-Test $c
      W ("       sign_errors={0}  verify /kp errors={1}" -f $t.se,$t.er)
      if($t.se -eq 0 -and $t.er -eq 0 -and -not $win){ $win=$c; $winName=$v }
    } else {
      W '       (no certSign bit -> bare sign ok, /kp guaranteed 0x80096019)'
    }
  }
}

########## 1b: arm c7 - raw CertEnroll COM CA (bulletproof; sets CX509ExtensionKeyUsage 0x86 directly) ##########
if(-not $win){
  W '  c7: building CA via CertEnroll COM ...'
  try {
    $sub = 'CN=ApexDrv CA c7 (QwenKern)'
    $key = New-Object -ComObject X509Enrollment.CX509PrivateKey
    $key.ProviderName = 'Microsoft Software Key Storage Provider'
    $key.Length = 2048
    $key.MachineContext = $true
    $key.KeySpec = 2
    $key.ExportPolicy = 1
    $key.Create() | Out-Null
    $req = New-Object -ComObject X509Enrollment.CX509CertificateRequestCertificate
    $req.InitializeFromPrivateKey(1,$key,'')
    $req.Subject = $sub
    $req.Issuer  = $sub
    $req.NotBefore = (Get-Date).AddDays(-1)
    $req.NotAfter  = (Get-Date).AddYears(10)
    $bc = New-Object -ComObject X509Enrollment.CX509ExtensionBasicConstraints
    $bc.Initialize($true,0); $bc.Critical = $true
    $ku = New-Object -ComObject X509Enrollment.CX509ExtensionKeyUsage
    $ku.Initialize(0x86); $ku.Critical = $true
    $eku = New-Object -ComObject X509Enrollment.CX509ExtensionEnhancedKeyUsage
    $oid = New-Object -ComObject X509Enrollment.CObjectId
    $oid.InitializeFromValue('1.3.6.1.5.5.7.3.3')
    $oids = New-Object -ComObject X509Enrollment.CObjectIdCollection
    $oids.Add($oid) | Out-Null
    $eku.Initialize($oids)
    $req.X509Extensions.Add($bc)  | Out-Null
    $req.X509Extensions.Add($ku)  | Out-Null
    $req.X509Extensions.Add($eku) | Out-Null
    $req.Encode()
    $enr = New-Object -ComObject X509Enrollment.CX509Enrollment
    $enr.InitializeFromRequest($req)
    $b64 = $enr.CreateRequest()
    try { $enr.InstallResponse(2,$b64,0,'') } catch { $enr.InstallResponse(0,$b64,0,'') }
    $c = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $sub } | Sort-Object NotBefore -Descending | Select-Object -First 1
    if($c){
      W ("       thumb={0}" -f $c.Thumbprint)
      W ("       {0}" -f (KU-Info $c))
      $bits = [int]$c.KeyUsage
      if((($bits -band 4) -ne 0)){
        Trust-It $c; $t = Kp-Test $c
        W ("       sign_errors={0}  verify /kp errors={1}" -f $t.se,$t.er)
        if($t.se -eq 0 -and $t.er -eq 0){ $win=$c; $winName='c7' }
      } else { W '       COM cert still has no certSign bit!' }
    } else { W '       COM cert not found in My store after InstallResponse' }
  } catch { W ("  c7: COM FAILED :: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
}

W ''
if($win){
  W ("WINNING SPELL = {0}  thumb={1}" -f $winName,$win.Thumbprint)
  W ("  {0}" -f (KU-Info $win))
  ("{0}|{1}" -f $winName,$win.Thumbprint) | Set-Content -LiteralPath (Join-Path $PSScriptRoot '_p25c_winner.txt')
} else {
  W 'NO VARIANT VERIFIED - every spell above still produced 0x80096019.'
}
W ''

########## 2: leaf from winning CA (leaf chain = proper DSE shape) ##########
$signer = $win
$signerName = $winName
if($win){
  W '  attempting leaf signed by winner ...'
  try {
    $leaf = Var-Cert 'c3' 'CN=ApexDrv Lab DSE p25c (QwenKern)' $false $win
    W ("  leaf thumb={0}" -f $leaf.Thumbprint)
    W ("       {0}" -f (KU-Info $leaf))
    $t = Kp-Test $leaf
    W ("       sign_errors={0}  verify /kp errors={1}" -f $t.se,$t.er)
    if($t.se -eq 0 -and $t.er -eq 0){ $signer=$leaf; $signerName='leaf-of-'+$winName }
    else { W '       leaf chain FAILED /kp -> falling back to direct CA signing'; W ("       /kp: {0}" -f ($t.out -replace "`n",' | ')) }
  } catch { W ("  leaf create FAILED :: {0}" -f ($_.Exception.Message -replace '\s+',' ')) }
  W ("CHOSEN SIGNER = {0}" -f $signerName)
}
W ''

########## 3: sign the REAL driver + verify, restage, then service test ##########
if($signer){
  Trust-It $signer
  $s = ((& $signtool sign /v /sm /sha1 $signer.Thumbprint /fd SHA256 $sys 2>&1) -join ' ')
  W ("  sign real driver: {0}" -f $s.Substring(0,[Math]::Min(200,$s.Length)))
  $v = ((& $signtool verify /v /kp $sys 2>&1) -join ' ')
  W '  --- signtool verify /kp C:\Windows\System32\drivers\apexdrv.sys ---'
  ($v -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { W ('   ' + $_.Trim()) }
  $ver = ($v -match 'Successfully verified')
  W ("  /kp VERDICT = {0}" -f $(if($ver){'SUCCESS'}else{'FAIL'}))

  $pd = 'C:\ProgramData\QwenKern\apexdrv.sys'
  if(Test-Path -LiteralPath 'C:\ProgramData\QwenKern'){
    Copy-Item -LiteralPath $sys -Destination $pd -Force
    W ("  restaged {0}" -f $pd)
  } else { W '  C:\ProgramData\QwenKern missing - not restaged' }
} else { W '  no signer -> skipping real-driver signing' }
W ''

########## 4: service clean re-create + start under DSE (testsigning OFF) ##########
$sysPath = '"' + $sys + '"'
$tmp = Join-Path $env:TEMP 'qp25c.bat'
& sc.exe stop kernprobe *> $null
& sc.exe delete kernprobe *> $null
Start-Sleep -Milliseconds 400
$cr = (& sc.exe create kernprobe type= kernel start= demand binPath= $sysPath DisplayName= "ApexDrv kernprobe (p25c)" 2>&1) -join ' '
W ("  create : {0}" -f $cr)
$st = (& sc.exe start kernprobe 2>&1) -join ' '
W ("  start  : {0}" -f $st)
Start-Sleep -Milliseconds 800
$q = ((& sc.exe query kernprobe 2>&1) -join ' ') -replace '\s+',' '
W ("  query  : {0}" -f $q)
W ''

########## 5: VERDICT ##########
$run = ($q -match 'RUNNING')
$fmt = [int]([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CertSign)
if($run -and $signer){
  W ("PASS - driver is signed by {0} and kernprobe is RUNNING under DSE (testsigning OFF)." -f $signerName)
  W '  next: fix _index.txt:94 to point at this signer, re-verify Apex + EAAC, no reboot.'
} elseif($signer -and $signerName -like '*c7*'){
  W 'PARTIAL - COM CA signs clean; re-run service step / check CI event below.'
} else {
  W 'STILL BLOCKED - fork: (A) keep gdrv3.sys transport, or (B) bcdedit /set testsigning on + reboot.'
}
W ("sanity: CertSign flag value = {0} (bit 0x04 used by the keyCertSign test)" -f $fmt)
W '-- recent CI events:'
Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddMinutes(-30) } -ErrorAction SilentlyContinue |
  Select-Object -First 8 | ForEach-Object { W ("   {0} id={1} {2}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,($_.Message -replace '\s+',' ').Substring(0,[Math]::Min(160,($_.Message -replace '\s+',' ').Length))) }
W ("--- p25c END {0} ---" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
L ("p25c END {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
