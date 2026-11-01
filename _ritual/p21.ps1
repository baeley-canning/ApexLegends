# p21 - ELEVATED FIX: clear TESTSIGNING (the proven EAAC/Javelin kill-flag) while keeping lab drivers loadable.
# Self-elevates (UAC). Reports first, then: trust lab-driver certs, back up BCD, bcdedit testsigning off.
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p21.txt'
$run = Join-Path $PSScriptRoot 'run21.log'
function W($t){ $t | Add-Content -LiteralPath $o }
function L($t){ $t | Add-Content -LiteralPath $run }

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  L ("p21 launcher (unelevated) $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') - raising UAC ...")
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  L 'UAC raised. Approve it, then read p21.txt.'
  exit
}
"=== p21 ELEVATED $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME user=$env:USERNAME ===" | Set-Content -LiteralPath $o
W 'GOAL: remove TESTSIGNING from the boot config (proven trigger of "Security Violation : Test or debug mode must be disabled to start the game")'
W '      while ensuring no local driver depends on test-signing.'

W ''
W '########## A state BEFORE ##########'
W ("  SystemStartOptions = [{0}]" -f ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions))
W ("  bcdedit /enum current /v: {0}" -f ((((& bcdedit.exe /enum '{current}' /v 2>&1) -join ' ~ ') -replace '\s+',' ')))
W ("  bcdedit /enum all (flag lines): {0}" -f ((((& bcdedit.exe /enum all 2>&1) | Where-Object { $_ -match 'testsigning|nointegritychecks|debug\b|hypervisor' }) -join ' ~ ') -replace '\s+',' '))

W ''
W '########## B lab drivers on disk (what could need testsigning) ##########'
$pattern = 'apexdrv|qwenkern|kernprobe|zzprobe|eaanticheat|gdrv|vgk|iqvw|easyanti|eac|javelin'
$targets = @()
foreach($dir in 'C:\Windows\System32\drivers','C:\ProgramData\QwenKern'){
  if(-not (Test-Path -LiteralPath $dir)){ continue }
  $targets += @(Get-ChildItem -LiteralPath $dir -Force -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.sys' -and $_.Name -match $pattern } | Select-Object -First 40)
}
$targets = @($targets | Select-Object -Unique -ExpandProperty FullName)
W ("  candidate .sys: {0}" -f ($targets -join ' | '))
$audit = @()
foreach($t in $targets){
  $s = Get-AuthenticodeSignature -LiteralPath $t -ErrorAction SilentlyContinue
  $sc = $s.SignerCertificate
  $selfsigned = if($sc){ ($sc.Subject -eq $sc.Issuer) } else { $true }
  $audit += [pscustomobject]@{ Path=$t; Status=[string]$s.Status; SelfSigned=$selfsigned
    Subject=$(if($sc){$sc.Subject}else{'(none)'}); Thumbprint=$(if($sc){$sc.Thumbprint}else{''}) }
  W ("  SIG {0,-14} selfsigned={1,-5} {2} | {3}" -f [string]$s.Status,$selfsigned,$t,$(if($sc){$sc.Subject}else{'(no signer cert)'}))
}
if(-not $audit){ W '  (no matching .sys found)' }

W ''
W '########## C trust certs of self-signed lab drivers (idempotent) ##########'
foreach($a in $audit){
  if(-not $a.Thumbprint){ W ("  NOT SIGNED AT ALL (no signer cert): {0}" -f $a.Path); continue }
  if($a.Status -eq 'Valid' -and -not $a.SelfSigned){ W ("  OK, already chains to a trusted root: {0}" -f $a.Path); continue }
  $cert = (Get-AuthenticodeSignature -LiteralPath $a.Path).SignerCertificate
  foreach($name in 'Root','TrustedPublisher'){
    $have = @(Get-ChildItem "Cert:\LocalMachine\$name" -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $a.Thumbprint })
    if($have){ W ("  already trusted in {0}: {1}" -f $name,$a.Thumbprint); continue }
    try {
      $cer = Join-Path $PSScriptRoot ('trusted_' + $a.Thumbprint + '.cer')
      [IO.File]::WriteAllBytes($cer, $cert.Export('Cert'))
      $st = New-Object System.Security.Cryptography.X509Certificates.X509Store($name,'LocalMachine')
      $st.Open('ReadWrite'); $st.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cer))); $st.Close()
      W ("  ADDED to {0}: {1} ({2})" -f $name,$a.Thumbprint,$cert.Subject)
    } catch { W ("  ADD FAILED {0} -> {1}: {2}" -f $a.Path,$name,$_.Exception.Message) }
  }
}
W '-- LocalMachine Root/TrustedPublisher certs matching lab names (post):'
foreach($name in 'Root','TrustedPublisher'){
  $c = @(Get-ChildItem "Cert:\LocalMachine\$name" -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -match 'apex|qwen|kern|probe|javelin|eac|test|sign' })
  W ("  {0}: {1}" -f $name,$(if($c){ ($c | ForEach-Object { $_.Subject }) -join ' ;; ' } else { '(none matching)' }))
}

W ''
W '########## D FIX: clear the boot flags ##########'
$bak = Join-Path $PSScriptRoot ('bcd_before_' + (Get-Date -f 'yyyyMMdd_HHmmss') + '.bcd')
W ("  bcdedit /export {0}: {1}" -f $bak, ((((& bcdedit.exe /export "$bak" 2>&1)) -join ' ~ ') -replace '\s+',' '))
foreach($set in @('testsigning off','nointegritychecks off','debug off')){
  $kv = $set.Split(' ')
  $out = ((& bcdedit.exe /set $kv[0] $kv[1] 2>&1) -join ' ~ ') -replace '\s+',' '
  W ("  bcdedit /set {0} -> [{1}] RC={2}" -f $set,$out,$LASTEXITCODE)
}

W ''
W '########## E state AFTER ##########'
W ("  SystemStartOptions = [{0}]" -f ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions))
W ("  bcdedit /enum current /v: {0}" -f ((((& bcdedit.exe /enum '{current}' /v 2>&1) -join ' ~ ') -replace '\s+',' ')))

W ''
W '########## F services / filters / staged driver packages ##########'
foreach($s in 'eaanticheat','EAAntiCheat','eaanticheat_loader','apexdrv','qwenkern'){
  W ("  sc query {0}: {1}" -f $s, ((((& sc.exe query $s 2>&1) -join ' ~ ') -replace '\s+',' ')))
}
W ("  fltmc filters: {0}" -f ((((& fltmc.exe filters 2>&1) -join ' ~ ') -replace '\s+',' ')))
W ("  driverquery apex/eaac: {0}" -f ((((& driverquery.exe /v 2>&1) | Where-Object { $_ -match 'apex|eaac|eac|javelin|qwen' }) -join ' ~ ') -replace '\s+',' '))
W '-- pnputil /enum-drivers (raw):'
W (((& pnputil.exe /enum-drivers 2>&1) -join "`n"))
W ''
W "-- p21 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
W 'NEXT: reboot, then run run22.cmd (post-reboot verification) and relaunch Apex.'
L ("p21 ELEVATED done $(Get-Date -f 'dd/MM/yyyy HH:mm:ss')")

