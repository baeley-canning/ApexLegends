# p25f - p25e exposed the real harness bug:
#   Try-Shape did `Trust-Root $cert` = it imported the SIGNER into LocalMachine\Root and never the
#   ISSUER. So every root->leaf shape (S2/S3/S4) had a ROOT that was in NO store ->
#   "A certificate chain processed, but terminated in a root certificate..." (CERT_E_UNTRUSTEDROOT
#   0x800B0109, which is why the scoreboard showed codes=[] - signtool prints only the sentence).
#   Only the self-signed shapes S1/S5 had a trusted root, and those returned 0x80096019.
# So the S2/S3/S4 verdicts are VOID, not failures: the basic-constraints check had already PASSED
# for them (the complaint was one level higher, the root). p25f imports the issuer root and
# re-verifies the SAME already-signed files with /kp. First shape at 0 errors -> sign the live
# driver and attempt a real DSE load with testsigning still OFF.
$ErrorActionPreference = 'Continue'
$o   = Join-Path $PSScriptRoot 'p25f.txt'
$log = Join-Path $PSScriptRoot 'run25f.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function L($t){ $t | Add-Content -LiteralPath $log }
if(-not $adm){
  L ("p25f (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; elevated p25f writes p25f.txt'
  exit
}
"=== p25f ISSUER-TRUST REPAIR $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') PS=$($PSVersionTable.PSVersion) ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }
function WL($t){ W $t; L $t }

$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
$sig = @(
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
W ("signtool = {0}" -f $sig)

function Keep-Useful($txt){
  @(($txt -split "`n") | Where-Object { $_ -match 'Issued to|Issued by|Error|error|SignTool|Successfully|Chain|Signature|Version of|Hash of|0x8|verified|Serial|Digest|The signature|The certificate|trust provider|not trusted' }) |
    ForEach-Object { '      ' + $_.Trim() } | Select-Object -First 30
}
function ReVerify($file){
  if(-not (Test-Path -LiteralPath $file)){ return $null }
  $v  = ((& $sig verify /v /kp $file 2>&1) -join "`n")
  $er = if($v -match 'Number of errors:\s*(\d+)'){ [int]$Matches[1] } else { -1 }
  $codes = @(($v -split "`n") | Where-Object { $_ -match '0x8[0-9A-Fa-f]{7}' } | ForEach-Object { ($_ -replace '.*?(0x8[0-9A-Fa-f]{7}).*','$1').Trim() } | Select-Object -Unique)
  $sentence = @(($v -split "`n") | Where-Object { $_ -match 'chain processed, but terminated|WinVerifyTrust returned error' } | ForEach-Object { $_.Trim() } | Select-Object -First 1)
  return @{ er=$er; codes=($codes -join ','); sentence=$sentence; raw=$v }
}


########## 1: import the ISSUER root (the step p25e never did) ##########
W '########## 1: import the S2 ROOT CA into LocalMachine\Root ##########'
$rt = Get-ChildItem 'Cert:\LocalMachine\My\1A5520EED6638BEC2A5EE297D3FF984B2CACF889' -ErrorAction SilentlyContinue
if(-not $rt){ $rt = @(Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match 'ApexDrv S2 Root CA' }) | Select-Object -First 1 }
W ("  S2 root CA in My = {0}" -f [bool]$rt)
if($rt){
  $cer = Join-Path $PSScriptRoot '_p25e_S2root.cer'
  if(-not (Test-Path -LiteralPath $cer)){ Export-Certificate -Cert $rt -FilePath $cer -Force | Out-Null }
  $rc = ((& certutil.exe -addstore -f Root $cer 2>&1) -join ' ')
  W ("  certutil -addstore -f Root S2root.cer -> {0}" -f ($rc -replace '\s+',' '))
  W ("  root now in LocalMachine\Root = {0}" -f [bool](Get-ChildItem 'Cert:\LocalMachine\Root\1A5520EED6638BEC2A5EE297D3FF984B2CACF889' -ErrorAction SilentlyContinue))
  W '  --- certutil truth on the root that is now trusted ---'
  (& certutil.exe -dump $cer 2>&1) | Where-Object { $_ -match 'Subject:|Issuer:|Subject Type|Key Usage|Certificate Signing|2\.5\.29\.19|2\.5\.29\.15|Root Certificate|Critical|Length' } | ForEach-Object { W ('    ' + $_.Trim()) }
}
W ''

########## 2: re-verify the p25e shape files, no re-sign ##########
W '########## 2: /kp re-verify of the already-signed p25e shape files (issuer now trusted) ##########'
$shapes = @('S2','S2tp','S3','S3tp','S4','S4tp','S1','S5')
$winFile = $null; $winLeaf = $null; $winTag = $null
foreach($t in $shapes){
  $f = Join-Path $PSScriptRoot ('_p25e_{0}.sys' -f $t)
  if(-not (Test-Path -LiteralPath $f)){ W ("  {0,-5} (no file)" -f $t); continue }
  $r = ReVerify $f
  $cn = switch($t){ 'S1' {'S1 SelfSigned'} 'S5' {'S5 SelfSigned'} default {'S2 Leaf'} }
  $lc = @(Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match ('CN=ApexDrv ' + $cn) }) | Select-Object -First 1
  W ("  {0,-5} kp_errors={1,-3} codes=[{2}] {3}" -f $t,$r.er,$r.codes,$r.sentence)
  if($r.er -ne 0){ Keep-Useful $r.raw | ForEach-Object { W $_ } }
  if($r.er -eq 0 -and -not $winFile){ $winFile=$f; $winTag=$t; $winLeaf=$lc }
}
W '  --- contrast: p25e legacy sweep files (self-signed CAs ALREADY trusted in Root) ---'
foreach($lf in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '_p25e_L*.sys')){
  $r = ReVerify $lf.FullName
  W ("  {0,-22} kp_errors={1,-3} codes=[{2}] {3}" -f $lf.Name,$r.er,$r.codes,$r.sentence)
}
W ''

########## 3: real driver with the winning signer + DSE load attempt ##########
W '########## 3: real driver ##########'
$q = ''
if($winFile){
  W ("  WINNER shape {0} -> signer {1}  {2}" -f $winTag,$winLeaf.Thumbprint,$winLeaf.Subject)
  W ("  winner chain file = {0}" -f $winFile)
  $bak = 'C:\Windows\System32\drivers\apexdrv.sys.bak_p25f'
  if(-not (Test-Path -LiteralPath $bak)){ Copy-Item -LiteralPath $sys -Destination $bak -Force; W ("  backup -> {0}" -f $bak) } else { W ("  backup already present -> {0}" -f $bak) }
  $sp = ((& $sig sign /v /sm /sha1 $winLeaf.Thumbprint /fd SHA256 $sys 2>&1) -join "`n")
  W ("  sign  : {0}" -f ((($sp -split "`n") | Where-Object { $_ -match 'Successfully signed|Number of errors' } | ForEach-Object { $_.Trim() } | Select-Object -First 2) -join ' | '))
  $lv = ReVerify $sys
  W ("  live verify /kp errors = {0} codes=[{1}]" -f $lv.er,$lv.codes)
  Keep-Useful $lv.raw | ForEach-Object { W $_ }
  W ("  Get-AuthenticodeSignature = {0}" -f (Get-AuthenticodeSignature $sys).Status)
  $stage = 'C:\ProgramData\QwenKern\apexdrv.sys'
  Copy-Item -LiteralPath $sys -Destination $stage -Force
  W ("  restage {0} exists={1} size={2}" -f $stage,(Test-Path -LiteralPath $stage),(Get-Item -LiteralPath $stage).Length)
  $sysQ = '"' + $sys + '"'
  W ("  stop   : {0}" -f (((& sc.exe stop kernprobe 2>&1) -join ' ') -replace '\s+',' '))
  W ("  delete : {0}" -f (((& sc.exe delete kernprobe 2>&1) -join ' ') -replace '\s+',' '))
  Start-Sleep -Milliseconds 600
  W ("  create : {0}" -f (((& sc.exe create kernprobe type= kernel start= demand binPath= $sysQ DisplayName= 'ApexDrv kernprobe (p25f)' 2>&1) -join ' ') -replace '\s+',' '))
  W ("  start  : {0}" -f (((& sc.exe start kernprobe 2>&1) -join ' ') -replace '\s+',' '))
  Start-Sleep -Milliseconds 900
  $q = (((& sc.exe query kernprobe 2>&1) -join ' ') -replace '\s+',' ')
  W ("  query  : {0}" -f $q)
  W ("  testsigning: {0}" -f ((((& bcdedit.exe /enum '{current}' 2>&1) | Where-Object { $_ -match 'testsigning' }) -join ' ').Trim()))
}else{
  W '  NO WINNER - live driver untouched.'
}

########## 4: VERDICT ##########
W ''
W '########## 4: VERDICT ##########'
$run = ($q -match 'RUNNING')
if($winFile -and $run){
  W ("  PASS: shape {0} signs + verifies under /kp AND the kernel loaded it with testsigning OFF." -f $winTag)
  W ("  signer thumbprint = {0}" -f $winLeaf.Thumbprint)
  W '  -> lock this signer in the build/index, keep testsigning OFF, re-verify Apex + EAAC.'
}elseif($winFile){
  W ("  HALF: shape {0} is /kp-clean but sc start did not report RUNNING - read the start error above." -f $winTag)
  W '  start error 577 / 0x80070490-class = DSE still rejects -> fork: (A) gdrv3, (B) testsigning.'
}elseif($rt){
  W '  STILL BLOCKED: even with the issuer root trusted no shape reached /kp 0, so the block is the'
  W '  SHAPE/root itself, not the missing import. Compare codes above:'
  W '    0x800B0109 on the leaf shapes with 0x80096019 on the self-signed shapes = the kernel policy'
  W '    wants a real chain whose root it accepts; the local root is already accepted by /kp here.'
}else{
  W '  STILL BLOCKED: no S2 root CA found in My.'
}
W '  -- CI events (last 30 min) --'
foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddMinutes(-30)} -MaxEvents 12 -ErrorAction SilentlyContinue)){
  W ("    {0} id={1} {2}" -f $e.TimeCreated.ToString('HH:mm:ss'),$e.Id,($e.Message -split "`n")[0])
}
W '  -- ROLLBACK driver: Copy-Item -LiteralPath "C:\Windows\System32\drivers\apexdrv.sys.bak_p25f" -Destination "C:\Windows\System32\drivers\apexdrv.sys" -Force ; sc.exe stop kernprobe ; sc.exe delete kernprobe'
W '  -- ROLLBACK root  : certutil -delstore Root 1A5520EED6638BEC2A5EE297D3FF984B2CACF889'
"=== p25f END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Add-Content -LiteralPath $o
L "p25f done $(Get-Date -f 'HH:mm:ss') win=$winTag run=$run"

