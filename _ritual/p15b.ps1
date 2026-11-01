$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p15b.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"=== p15b $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm ===" | Set-Content -LiteralPath $o

W '########## A existence triple-check ##########'
foreach($p in 'C:\Windows\System32\drivers\eaanticheat.sys','C:\Windows\System32\drivers\apexdrv.sys','C:\Windows\System32\drivers\gdrv3.sys','C:\Windows\System32\drivers\EAAntiCheat.sys'){
  $raw = (& cmd.exe /c "if exist `"$p`" (echo YES) else (echo NO)") -join ''
  W ("  {0,-52} TestPath={1,-6} IO={2,-6} raw={3}" -f $p, (Test-Path -LiteralPath $p), ([IO.File]::Exists($p)), $raw)
}
W '-- raw dir listing of drivers dir (ea|apex|javelin), incl hidden:'
Get-ChildItem 'C:\Windows\System32\drivers' -Force | Where-Object { $_.Name -match 'ea|apex|javelin' } | ForEach-Object { W ("   [{0,10}] {1} {2}" -f $_.Length, $_.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'), $_.FullName) }

W ''
W '########## B setupapi install history ##########'
foreach($log in 'C:\Windows\INF\setupapi.dev.log','C:\Windows\INF\setupapi.app.log'){
  if(Test-Path -LiteralPath $log){
    W "-- $log"
    $m = Select-String -LiteralPath $log -Pattern 'eaanticheat|apexdrv' -ErrorAction SilentlyContinue
    W ("   matches={0}" -f (@($m).Count))
    if($m){ $m | Select-Object -Last 45 | ForEach-Object { W ("   L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) } }
  } else { W "-- $log MISSING" }
}

W ''
W '########## C DriverStore INF scan for eaanticheat/apexdrv ##########'
$hits = 0
Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Recurse -Filter '*.inf' -Force -ErrorAction SilentlyContinue | ForEach-Object {
  if(Select-String -LiteralPath $_.FullName -Pattern 'eaanticheat|apexdrv' -Quiet -ErrorAction SilentlyContinue){ W ("   INFMATCH {0}" -f $_.FullName); $hits++ }
}
W ("   total inf matches={0}" -f $hits)
W '-- FileRepository dirs matching eaa|apex|javelin|game:'
Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'eaa|apex|javelin|game' } | ForEach-Object { W ("   DIR {0}" -f $_.FullName) }

W ''
W '########## D service + filter state ##########'
foreach($n in 'EAAntiCheat','eaanticheat','EAAntiCheatService','apexdrv','kernprobe','zzprobe'){
  $q = (& sc.exe query $n 2>&1) -join ' ~ '
  W ("  sc query {0}: {1}" -f $n, ($q -replace '\s+',' '))
}
$f = (& fltmc.exe filters 2>&1) -join ' | '
W ("  fltmc filters: {0}" -f ($f -replace '\s+',' '))


W ''
W '########## E Instances + Altitude + SupportedFeatures ##########'
foreach($n in 'EAAntiCheat','eaanticheat','apexdrv','zzprobe','kernprobe'){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
  if(Test-Path $k){
    $p = Get-ItemProperty $k
    W ("   KEY {0} Type={1} Start={2} Tag={3} SupportedFeatures={4} Altitude(Instances)={5}" -f $n, $p.Type, $p.Start, $p.Tag, $p.SupportedFeatures, $(if(Test-Path "$k\Instances"){ (Get-ChildItem "$k\Instances" | ForEach-Object { (Get-ItemProperty $_.PSPath).Altitude }) -join ',' } else { '(none)' }))
  } else { W "   KEY $n MISSING" }
}

W ''
W '########## F CI / HVCI / DeviceGuard registry ##########'
foreach($k in 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config','HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard','HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'){
  if(Test-Path $k){
    W "  [$k]"
    (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { W ("     {0} = {1}" -f $_.Name, $_.Value) }
  } else { W "  [$k] MISSING" }
}
W '-- CI operational log id histogram (72h) + recent 3004/3010/3033/3077:'
try {
  $ev = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddHours(-72)} -ErrorAction Stop)
  $ev | Group-Object Id | ForEach-Object { W ("   id={0} count={1}" -f $_.Name, $_.Count) }
  $ev | Where-Object { $_.Id -in 3004,3010,3033,3077 } | Select-Object -First 12 | ForEach-Object {
    $mm = ($_.Message -replace '\s+',' ')
    W ("   [{0}] {1} :: {2}" -f $_.Id, $_.TimeCreated.ToString('dd/MM HH:mm:ss'), $mm.Substring(0, [Math]::Min(200, $mm.Length)))
  }
} catch { W "   CI log read failed: $($_.Exception.Message)" }

W ''
W '########## G EA/Qwen certs + signature status ##########'
$r = @(& certutil.exe -store Root 2>&1 | Select-String -Pattern 'AAA Certificate Services|Electronic Arts|DigiCert|Sectigo|Apex' | ForEach-Object { $_.Line.Trim() })
W ("  certutil Root matches ({0}): {1}" -f $r.Count, ($r -join ' ~ '))
foreach($st in 'Cert:\LocalMachine\Root','Cert:\LocalMachine\CA','Cert:\LocalMachine\TrustedPublisher','Cert:\LocalMachine\TrustedPeople'){
  $m = @(Get-ChildItem $st -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'Electronic Arts|EA SPEAR|QwenKern|Apex' } | ForEach-Object { ("{0} | {1} | exp {2} | {3}" -f $_.PSChildName, $_.Subject, $_.NotAfter, $_.Thumbprint) })
  W ("  {0}: {1}" -f $st, ($m -join ' ~ '))
}
foreach($f in 'C:\Windows\System32\drivers\apexdrv.sys','C:\ProgramData\QwenKern\apexdrv.sys','C:\Program Files\EA\AC\EAAntiCheat.GameService.exe','C:\Program Files\EA\AC\EAAntiCheat.Installer.exe'){
  if(Test-Path -LiteralPath $f){
    $s = Get-AuthenticodeSignature -LiteralPath $f
    W ("  SIG {0} :: {1} | signer={2} | issuer={3}" -f $f, $s.Status, $s.SignerCertificate.Subject, $s.SignerCertificate.Issuer)
  } else { W "  SIG $f MISSING" }
}

W ''
W '########## H driver delivery artefacts ##########'
foreach($d in 'C:\ProgramData\eaanticheat','C:\Program Files\EA Games\Apex','C:\Users\New User\AppData\Local\Electronic Arts\EA Desktop\AC2'){
  if(Test-Path -LiteralPath $d){
    W "-- $d (recursive, first 40):"
    @(Get-ChildItem -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 40) | ForEach-Object { W ("   {0,12} {1} {2}" -f $_.Length, $_.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'), $_.FullName) }
  } else { W "-- $d MISSING" }
}
W '-- Apex *.sys files:'
if(Test-Path 'C:\Program Files\EA Games\Apex'){ Get-ChildItem 'C:\Program Files\EA Games\Apex' -Recurse -Force -File -Filter '*.sys' -ErrorAction SilentlyContinue | ForEach-Object { W ("   SYS {0,12} {1}" -f $_.Length, $_.FullName) } }
W '-- EA uninstall/install registry records:'
foreach($k in 'HKLM:\SOFTWARE\Electronic Arts','HKLM:\SOFTWARE\WOW6432Node\Electronic Arts','HKLM:\SOFTWARE\EA Games','HKLM:\SOFTWARE\WOW6432Node\EA Games'){
  if(Test-Path $k){ W "   $k :"; Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { W ("     {0}" -f $_.PSChildName) } } else { W "   $k MISSING" }
}

"=== END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Add-Content -LiteralPath $o
W "-- p15b done"

