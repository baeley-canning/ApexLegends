# p24 - DSE ground truth + CERT REPAIR for our lab driver.
# Goal: with testsigning OFF (the p21 fix that stops the EAAC "Security Violation" popup),
# can C:\Windows\System32\drivers\apexdrv.sys still be started as the kernprobe service?
#
# Live evidence (Application log id 26 + CodeIntegrity id 3004) says NO today:
#   "Windows is unable to verify the image integrity of ...apexdrv.sys because file hash
#    could not be found on the system"  ->  sc start kernprobe = ERROR 577
#   STATUS_INVALID_IMAGE_HASH, even though the signer cert (apexdrv dev, self-signed) is in
#   LocalMachine\Root + TrustedPublisher and Get-AuthenticodeSignature says Valid.
#
# Because temp\drv\install.cmd built its cert with plain
#   New-SelfSignedCertificate -Type CodeSigningCert ...
# it has NO BasicConstraints extension (both dev certs report BC=ABSENT, AKI=ABSENT).
# Kernel CI cannot terminate an embedded-signature chain on a non-ca root, so DSE refuses it.
# Repair = one properly formed self-signed cert with BasicConstraints ca=1 (critical) + Code
# Signing EKU, dropped into Root + TrustedPublisher, then re-sign apexdrv.sys and re-test.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p24.txt'
$log = Join-Path $PSScriptRoot 'run24.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p24 (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; the elevated p24 writes p24.txt'
  exit
}
"=== p24 DSE GROUND TRUTH + CERT REPAIR $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$bak = $sys + '.bak_p24'
$subject = 'CN=ApexDrv Lab DSE (QwenKern)'
$signtool = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

W '########## 0: environment truth ##########'
$sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
W ("  SystemStartOptions = [{0}]" -f $sso)
W ("  testsigning in booted cmdline = {0}  (False is REQUIRED for the EAAC gate)" -f ($sso -match 'TESTSIGNING'))
try { W ("  SecureBoot = {0}" -f (Confirm-SecureBootUEFI)) } catch { W ("  SecureBoot = (n/a: {0})" -f ($_.Exception.Message -replace '\s+',' ')) }
W ("  signtool  = {0}" -f $signtool)
W ("  driver = {0} exists={1} size={2} lastWrite={3}" -f $sys,(Test-Path -LiteralPath $sys),$(if(Test-Path -LiteralPath $sys){(Get-Item -LiteralPath $sys).Length}else{'-'}),$(if(Test-Path -LiteralPath $sys){(Get-Item -LiteralPath $sys).LastWriteTime}else{'-'}))
W ("  current kernel transport gdrv3 = {0}" -f (((& sc.exe query gdrv3 2>&1) -join ' ') -replace '\s+',' '))

W ''
W '########## 1: BASELINE - sc start kernprobe as-shipped (expect FAILED 577) ##########'
W ("  sc stop : {0}" -f ((((& sc.exe stop kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 2
W ("  sc start: {0}" -f ((((& sc.exe start kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 2
W ("  sc query: {0}" -f ((((& sc.exe query kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
$bs = Get-AuthenticodeSignature -LiteralPath $sys
W ("  baseline sig status = {0} signer = {1}" -f $bs.Status,$bs.SignerCertificate.Subject)
$bci = Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 40 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'apexdrv' } | Select-Object -First 1
W ("  latest CI 3004      = {0}" -f $(if($bci){ $bci.TimeCreated.ToString('HH:mm:ss') + ' :: ' + (($bci.Message -replace '\s+',' ').Trim()) } else { '(none)' }))

W ''
W '########## 2: build a kernel-valid self-signed code-signing cert (BasicConstraints ca=1) ##########'
$c = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object { $_.Subject -eq $subject } | Select-Object -First 1
if($c){ W ("  reusing {0} thumb={1}" -f $subject,$c.Thumbprint) }
else {
  try {
    $c = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject `
      -CertStoreLocation 'Cert:\LocalMachine\My' `
      -KeyUsage DigitalSignature -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
      -NotAfter (Get-Date).AddYears(5) `
      -TextExtension @('2.5.29.19={critical}{text}ca=1')
    W ("  created {0} thumb={1} notAfter={2}" -f $subject,$c.Thumbprint,$c.NotAfter)
  } catch { W ("  create FAILED: {0}" -f $_.Exception.Message) }
}
if($c){
  $bc = $c.Extensions['2.5.29.19']
  W ("  cert check: BasicConstraints present={0} cA={1} critical={2} AKI={3} SKI={4} EKU={5}" -f `
     ($null -ne $bc),$(if($bc){$bc.CertificateAuthority}else{'-'}),$(if($bc){$bc.Critical}else{'-'}), `
     ($null -ne $c.Extensions['2.5.29.35']),($null -ne $c.Extensions['2.5.29.14']), `
     (($c.EnhancedKeyUsageList | ForEach-Object { $_.FriendlyName }) -join ','))
  $cer = Join-Path $PSScriptRoot 'apexdrv_lab_dse.cer'
  Export-Certificate -Cert $c -FilePath $cer -Force | Out-Null
  foreach($st in 'Root','TrustedPublisher'){
    Import-Certificate -FilePath $cer -CertStoreLocation ("Cert:\LocalMachine\$st") | Out-Null
    W ("  imported -> LocalMachine\{0}" -f $st)
  }
}

W ''
W '########## 3: re-sign apexdrv.sys with that cert (shipped file kept as .bak_p24) ##########'
if(-not (Test-Path -LiteralPath $bak)){ Copy-Item -LiteralPath $sys -Destination $bak -Force; W ("  backup -> {0}" -f $bak) }
else { W ("  backup already present -> {0}" -f $bak) }
if($signtool -and $c){
  W '  -- signtool sign:'
  W (((& $signtool sign /v /sm /sha1 $c.Thumbprint /fd SHA256 $sys 2>&1) -join "`n"))
  W '  -- signtool verify /kp:'
  W (((& $signtool verify /v /kp $sys 2>&1) -join "`n"))
} elseif($c){
  W '  !! signtool not found; falling back to Set-AuthenticodeSignature'
  Set-AuthenticodeSignature -LiteralPath $sys -Certificate $c | ForEach-Object { W ("  set-auth: {0}" -f $_.Status) }
}
$ns = Get-AuthenticodeSignature -LiteralPath $sys
W ("  new sig status = {0} signer = {1}" -f $ns.Status,$ns.SignerCertificate.Subject)

W ''
W '########## 4: clean service object + start under DSE (testsigning OFF) ##########'
W ("  {0}" -f ((((& sc.exe stop kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
W ("  {0}" -f ((((& sc.exe delete kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 2
W ("  sc create: {0}" -f ((((& sc.exe create kernprobe type= kernel start= demand binPath= System32\drivers\apexdrv.sys 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 1
W ("  sc start : {0}" -f ((((& sc.exe start kernprobe 2>&1) -join ' ~ ')) -replace '\s+',' '))
Start-Sleep -Seconds 2
$q = ((& sc.exe query kernprobe 2>&1) -join ' ')
W ("  sc query : {0}" -f ($q -replace '\s+',' '))

W ''
W '########## 5: RESULT / NEXT ACTION ##########'
if($q -match 'RUNNING'){
  W '  PASS: apexdrv.sys started under DSE with testsigning OFF.'
  W '  => the 577 root cause was the missing BasicConstraints ca=1 (plain New-SelfSignedCertificate'
  W '     -Type CodeSigningCert omits it; temp\drv\install.cmd used exactly that form).'
  W '  => the lab kernel driver and the closed EAAC gate are compatible: NO reboot, NO testsigning.'
  W '     Restage C:\ProgramData\QwenKern\apexdrv.sys from the same re-signed blob.'
} else {
  W '  STILL BLOCKED on the embedded-signature path.'
  W '  -> fallback A (recommended): keep testsigning OFF (EAAC gate satisfied) and let gdrv3.sys'
  W '     carry the kernel path (see ext/gio.py: "No own driver is used").'
  W '  -> fallback B: only if apexdrv must load, bcdedit /set testsigning on + reboot - but EAAC'
  W '     pops again, so pair it with the p21 flag matrix.'
}
W '-- CodeIntegrity events matching apexdrv/kernprobe (last 10):'
$ci = @(Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 60 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'apexdrv|kernprobe' } | Select-Object -First 10)
if($ci){ $ci | ForEach-Object { W ('   {0} id={1} :: {2}' -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,(($_.Message -replace '\s+',' ').Trim())) } } else { W '   (none)' }
W '-- Service Control Manager driver-load events (last 10):'
$sy = @(Get-WinEvent -LogName System -MaxEvents 300 -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'Service Control Manager' -and $_.Message -match 'kernprobe|apexdrv|digital signature' } | Select-Object -First 10)
if($sy){ $sy | ForEach-Object { W ('   {0} id={1} :: {2}' -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,(($_.Message -replace '\s+',' ').Trim())) } } else { W '   (none)' }
W ''
W ('-- ROLLBACK: Copy-Item -LiteralPath "{0}" -Destination "{1}" -Force ; sc stop kernprobe ; sc delete kernprobe' -f $bak,$sys)
W "-- p24 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
