# p25g - p25f verdict changed the problem statement:
#   with the ISSUER root trusted, /kp walked root->leaf fine and then said, verbatim:
#     "SignTool Error: Signing Cert does not chain to a Microsoft Root Cert."
#   (S4, the ca=1 leaf, still says 0x80096019 - that shape is independently dead.)
# Two things are now unknown and both are cheap to discriminate:
#   Q1 Does /kp's "Microsoft Root" test match by NAME (-> a root spoofed as
#      "CN=Microsoft Root Certificate Authority 2011" passes) or by public key?
#   Q2 Does the KERNEL (ci.dll) apply the same Microsoft-root rule, or does it accept any
#      chain that terminates in a trusted local root?  /kp strictness != load behaviour.
# p25g answers Q1 with name-spoof shapes and Q2 with a real sc start probe, reading the
# Service Control Manager + CodeIntegrity events as ground truth.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25g.txt'
$log = Join-Path $PSScriptRoot 'run25g.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25g (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; elevated p25g writes p25g.txt'
  exit
}
"=== p25g MSROOT-DISCRIMINATOR $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') PS=$($PSVersionTable.PSVersion) ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }
function WL($t){ W $t; L $t }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$sig = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

function Keep-Useful($txt){
  @(($txt -split "`n") | Where-Object { $_ -match 'Issued to|Issued by|SignTool Error|Number of errors|Chain|Microsoft Root|0x8' }) |
    ForEach-Object { '      ' + $_.Trim() } | Select-Object -First 20
}
function ReVerify($file){
  $v  = ((& $sig verify /v /kp $file 2>&1) -join "`n")
  $er = if($v -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $codes = @(($v -split "`n") | Where-Object { $_ -match '0x8[0-9A-Fa-f]{7}' } | ForEach-Object { ($_ -replace '.*?(0x8[0-9A-Fa-f]{7}).*','$1').Trim() } | Select-Object -Unique)
  $msg = @(($v -split "`n") | Where-Object { $_ -match 'SignTool Error|does not chain|0x8' } | ForEach-Object { $_.Trim() } | Select-Object -First 2)
  return @{ er=$er; codes=($codes -join ','); msg=($msg -join ' / '); raw=$v }
}
function New-Cert2($sub,$ca,$eku,$kuList,$signer,$years){
  $p = @{ CertStoreLocation='Cert:\LocalMachine\My'; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048
          HashAlgorithm='SHA256'; Subject=$sub; NotAfter=(Get-Date).AddYears($years); Type='Custom' }
  $te = @()
  if($null -ne $ca){ $te += ('2.5.29.19={critical}{text}ca=' + $(if($ca){'1'}else{'0'})) }
  if($eku){ $te += '2.5.29.37={text}1.3.6.1.5.5.7.3.3' }
  if($te.Count){ $p.TextExtension = $te }
  if($kuList){ $p.KeyUsage = $kuList }
  if($signer){ $p.Signer = $signer }
  return (New-SelfSignedCertificate @p)
}

########## 0: host + baseline truth ##########
W '########## 0: host / DSE state / baseline signature ##########'
W ("  build: {0}" -f ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild + '.' + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR))
foreach($l in @((& bcdedit.exe /enum '{current}' 2>&1) | Where-Object { $_ -match 'testsigning|nointegrity|hypervisorlaunchtype|description' })){ W ('  bcd: ' + $l.Trim()) }
W ("  secureboot firmware = {0}" -f $(try{ [string](Confirm-SecureBootUEFI) }catch{ 'n/a' }))
W ("  live driver sig = {0}" -f ((Get-AuthenticodeSignature $sys).Status))
$ls = Get-AuthenticodeSignature $sys
W ("  live signer     = {0}" -f $(if($ls.SignerCertificate){ $ls.SignerCertificate.Subject + ' [' + $ls.SignerCertificate.Thumbprint + ']' }else{'(none)'}))
W ("  S2 root in Root = {0}" -f [bool](Get-ChildItem 'Cert:\LocalMachine\Root\1A5520EED6638BEC2A5EE297D3FF984B2CACF889' -ErrorAction SilentlyContinue))
W '  MS roots already in LocalMachine\Root:'
foreach($c in @(Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match 'CN=Microsoft' })){ W ('    ' + $c.Subject) }
W ''

########## 1: Q1 - is the /kp "Microsoft Root" test name-based? ##########
W '########## 1: name-spoof family (Q1: name or key?) ##########'
$names = @(
  @{ tag='S6lan'; sub='CN=Microsoft Root Certificate Authority 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' },
  @{ tag='S7win'; sub='CN=Microsoft Windows Production PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' },
  @{ tag='S8old'; sub='CN=Microsoft Root Certificate Authority 2010, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' },
  @{ tag='S9msf'; sub='CN=Microsoft Root Authority, OU=Microsoft Corporation, OU=Copyright (c) 1997 Microsoft Corp.' }
)
$KU = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]
$spoof = @()
foreach($n in $names){
  $r = New-Cert2 $n.sub $true $false ($KU::KeyCertSign -bor $KU::CrlSign) $null 20
  $lf = New-Cert2 ("CN={0} Leaf (QwenKern)" -f $n.tag) $false $true ($KU::DigitalSignature) $r 5
  $f = Join-Path $PSScriptRoot ('_p25g_{0}.sys' -f $n.tag)
  Copy-Item -LiteralPath $sys -Destination $f -Force
  $s = ((& $sig sign /v /sm /sha1 $lf.Thumbprint /fd SHA256 $f 2>&1) -join "`n")
  $se = if($s -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $v = ReVerify $f
  W ("  {0} root='{1}' sign_errors={2} kp_errors={3} codes=[{4}]" -f $n.tag,$r.Subject.Split(',')[0],$se,$v.er,$v.codes)
  W ("      {0}" -f $v.msg)
  if($v.er -ne 0){ Keep-Useful $v.raw | Select-Object -First 8 | ForEach-Object { W $_ } }
  $spoof += [pscustomobject]@{ tag=$n.tag; leaf=$lf; root=$r; file=$f; kp=$v.er }
}
$spoofWin = @($spoof | Where-Object { $_.kp -eq 0 }) | Select-Object -First 1

W '  --- controls ---'
$s2leaf = @(Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match 'CN=ApexDrv S2 Leaf' }) | Select-Object -First 1
foreach($c in @($s2leaf)){
  if($c){
    $f = Join-Path $PSScriptRoot '_p25g_S2ctl.sys'
    Copy-Item -LiteralPath $sys -Destination $f -Force
    & $sig sign /v /sm /sha1 $c.Thumbprint /fd SHA256 $f 2>&1 | Out-Null
    $v = ReVerify $f
    W ("  S2ctl (real local root, MS-root absent) kp_errors={0} codes=[{1}] {2}" -f $v.er,$v.codes,$v.msg)
    $vpa = (((& $sig verify /v /pa $f 2>&1) -join "`n") -match 'Number of errors:\s*(\d+)')
    W ("  S2ctl /pa (authenticode policy, MS-root NOT required) errors={0}" -f $(if($vpa){$Matches[1]}else{'-'}))
  }
}
W ''

########## 2: Q2 - does the KERNEL accept a trusted LOCAL root (no MS root)? ##########
function Kernel-Probe($cert,$label){
  W ("  --- probe {0} : signer {1} ---" -f $label,$cert.Subject)
  $bak = 'C:\Windows\System32\drivers\apexdrv.sys.bak_p25g'
  if(-not (Test-Path -LiteralPath $bak)){ Copy-Item -LiteralPath $sys -Destination $bak -Force; W ("  backup -> {0}" -f $bak) }
  $s = ((& $sig sign /v /sm /sha1 $cert.Thumbprint /fd SHA256 $sys 2>&1) -join "`n")
  $sl = (($s -split "`n") | Where-Object { $_ -match 'Successfully signed|Number of errors' }) -join ' | '
  W ("  sign   : {0}" -f $sl)
  $lv = ReVerify $sys
  W ("  live /kp errors={0} codes=[{1}] {2}" -f $lv.er,$lv.codes,$lv.msg)
  $stage = 'C:\ProgramData\QwenKern\apexdrv.sys'
  Copy-Item -LiteralPath $sys -Destination $stage -Force
  $sysQ = '"' + $sys + '"'
  W ("  stop   : {0}" -f (((& sc.exe stop kernprobe 2>&1) -join ' ').Trim()))
  W ("  delete : {0}" -f (((& sc.exe delete kernprobe 2>&1) -join ' ').Trim()))
  Start-Sleep -Milliseconds 700
  W ("  create : {0}" -f (((& sc.exe create kernprobe type= kernel start= demand binPath= $sysQ DisplayName= 'ApexDrv kernprobe (p25g)' 2>&1) -join ' ').Trim()))
  $t0 = Get-Date
  W ("  start  : {0}" -f (((& sc.exe start kernprobe 2>&1) -join ' ').Trim()))
  Start-Sleep -Milliseconds 1400
  $qq = (((& sc.exe query kernprobe 2>&1) -join ' ').Trim()) -replace '\s+',' '
  W ("  query  : {0}" -f $qq)
  $running = [bool]($qq -match 'RUNNING')
  W ("  ===> {0} load = {1}" -f $label,$(if($running){'RUNNING (DSE accepted)'}else{'REFUSED'}))
  foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=$t0} -MaxEvents 4 -ErrorAction SilentlyContinue)){
    W ("     SCM {0} id={1} {2}" -f $e.TimeCreated.ToString('HH:mm:ss'),$e.Id,(($e.Message -split "`n")[0]))
  }
  foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=$t0} -MaxEvents 4 -ErrorAction SilentlyContinue)){
    W ("     CI  {0} id={1} {2}" -f $e.TimeCreated.ToString('HH:mm:ss'),$e.Id,(($e.Message -split "`n")[0]))
  }
  return [pscustomobject]@{ label=$label; cert=$cert; run=$running; kp=$lv.er }
}

W '########## 2/3: real DSE probes (testsigning stays OFF) ##########'
$res = @()
if($s2leaf){ $res += Kernel-Probe $s2leaf 'S2 (local root, MS-root absent)' }
if($spoofWin){ $res += Kernel-Probe $spoofWin.leaf ('SPOOF {0} (root named like an MS root)' -f $spoofWin.tag) }
if((-not $s2leaf) -and (-not $spoofWin)){ W '  no cert available for the probe' }

########## 4: VERDICT ##########
W ''
W '########## 4: VERDICT ##########'
$q1 = if($spoofWin){ 'YES - /kp matched by NAME: a spoofed "Microsoft ..." root passed /kp with our own key.' } else { 'NO - /kp matched by key/thumbprint: name spoofing alone did not satisfy the MS-root test.' }
$q2 = if(@($res | Where-Object { $_.run }).Count -gt 0){ 'YES - ci.dll accepted a chain from a LOCAL self-signed root: testsigning OFF is achievable with self-signed, provided the root is trusted and the shape is clean.' } else { 'NO - ci.dll refused every self-signed chain, so the kernel does enforce the Microsoft-root rule here.' }
W ("  Q1 (/kp name vs key) -> {0}" -f $q1)
W ("  Q2 (kernel enforces MS root?) -> {0}" -f $q2)
$win = @($res | Where-Object { $_.run }) | Select-Object -First 1
if($win){
  W ''
  W ("  *** LOADED: {0} ***" -f $win.label)
  W ("  signer thumbprint = {0}" -f $win.cert.Thumbprint)
  W ("  sign command      = signtool sign /v /sm /sha1 {0} /fd SHA256 C:\Windows\System32\drivers\apexdrv.sys" -f $win.cert.Thumbprint)
  @(("thumb=" + $win.cert.Thumbprint),("label=" + $win.label),("subject=" + $win.cert.Subject),
    ("cmd=signtool sign /v /sm /sha1 " + $win.cert.Thumbprint + " /fd SHA256 C:\Windows\System32\drivers\apexdrv.sys"),
    ("stage=Copy-Item -LiteralPath C:\Windows\System32\drivers\apexdrv.sys -Destination C:\ProgramData\QwenKern\apexdrv.sys -Force")) |
    Set-Content -LiteralPath (Join-Path $PSScriptRoot '_p25g_winner.txt')
  W ("  winner file -> {0}" -f (Join-Path $PSScriptRoot '_p25g_winner.txt'))
  W '  NEXT: lock this signer in _index.txt, rebuild Apex + EAAC, re-verify with the same /kp + sc start pairing.'
}else{
  W '  NEXT fork if nothing loaded:'
  W '    (A) keep gdrv3.sys (drop apexdrv entirely), or'
  W '    (B) bcdedit /set testsigning on + reboot (self-signed then always loads; keep the S2 shape).'
}
W '  -- p25g leftovers: name-spoof certs are junk, sweep once a winner is locked --'
foreach($p in $spoof){ W ("    {0}  leaf={1}  root={2}" -f $p.tag,$p.leaf.Thumbprint,$p.root.Thumbprint) }
W '  -- ROLLBACK driver: Copy-Item -LiteralPath "C:\Windows\System32\drivers\apexdrv.sys.bak_p25g" -Destination "C:\Windows\System32\drivers\apexdrv.sys" -Force ; sc.exe stop kernprobe ; sc.exe delete kernprobe'
W '  -- ROLLBACK spoof roots: certutil -delstore Root <root thumbprint above>'
"=== p25g END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Add-Content -LiteralPath $o
L ("p25g done {0} loaded={1}" -f (Get-Date -f 'HH:mm:ss'), $(if($win){$win.label}else{'none'}))

