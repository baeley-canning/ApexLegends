$ErrorActionPreference='Continue'
$out='c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p13_dirs2.txt'
$sw=New-Object System.IO.StreamWriter($out,$false,(New-Object System.Text.UTF8Encoding($true)))
function W($s){$sw.WriteLine([string]$s);$sw.Flush()}
function SEC($s){W("");W("########## $s ##########")}
$adm=$false
try{$adm=(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
W("=== p13 dirs2 $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') admin=$adm ===")

SEC 'DeviceGuard CIM'
try{W(Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard|Format-List *|Out-String -Width 300)}catch{W("ERR $($_.Exception.Message)")}

SEC 'system drivers apex/ea/jav/sky'
try{W(Get-CimInstance Win32_SystemDriver|?{$_.Name -match 'apex|eaac|javelin|sky|qwen'}|Select Name,DisplayName,State,Started,StartMode,PathName|Format-Table -AutoSize|Out-String -Width 300)}catch{W("ERR $($_.Exception.Message)")}

SEC 'service keys'
foreach($n in 'apexdrv','eaanticheat','EAAntiCheat','skyfall','qwenkern'){
 $p="HKLM:\SYSTEM\CurrentControlSet\Services\$n"
 if(Test-Path $p){W("-- $p");try{W(Get-ItemProperty $p|Format-List *|Out-String -Width 300)}catch{W("ERR $($_.Exception.Message)")}}
 else{W("-- $p MISSING")}}

SEC 'sc query'
foreach($n in 'apexdrv','eaanticheat'){W("-- sc query $n");try{W(sc.exe query $n 2>&1|Out-String)}catch{W("ERR")}}

SEC 'apexdrv.sys signature + chain'
$f='C:\Windows\System32\drivers\apexdrv.sys'
if(Test-Path $f){try{
 $sig=Get-AuthenticodeSignature $f
 W("Status=$($sig.Status) Msg=$($sig.StatusMessage)")
 W("SignerSubj=$($sig.SignerCertificate.Subject)")
 W("SignerIss=$($sig.SignerCertificate.Issuer) NotAfter=$($sig.SignerCertificate.NotAfter) Thumb=$($sig.SignerCertificate.Thumbprint)")
 W("TimeStamper=$($sig.TimeStamperCertificate.Subject)")
 $ch=New-Object System.Security.Cryptography.X509Certificates.X509Chain
 $ch.ChainPolicy.RevocationMode='NoCheck'
 $c2=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($f)
 W("ChainBuild="+$ch.Build($c2)+" status="+(($ch.ChainStatus|%{$_.Status}) -join ';'))
 foreach($el in $ch.ChainElements){W("  el: $($el.Certificate.Subject) || $($el.Certificate.NotAfter)")}
 W(Get-Item $f|Select FullName,Length,CreationTime,LastWriteTime|Format-List|Out-String -Width 300)
 W("SHA256="+(Get-FileHash $f -Algorithm SHA256).Hash)
}catch{W("ERR $($_.Exception.Message)")}}else{W("MISSING $f")}

SEC 'apexdrv/eaac copies + hashes'
try{W(Get-ChildItem 'C:\Windows\System32\drivers','C:\Program Files\EA\AC','C:\Program Files\EA Games\Apex','C:\Program Files\EA Games\Apex\__Installer' -Recurse -Force -File -ErrorAction SilentlyContinue|?{$_.Name -match 'apexdrv|eaac|javelin|skyfall|qwen'}|Select FullName,Length,LastWriteTime,@{n='sha';e={(Get-FileHash $_.FullName -Algorithm SHA256).Hash}}|Format-Table -AutoSize|Out-String -Width 300)}catch{W("ERR $($_.Exception.Message)")}
try{W(Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Force -ErrorAction SilentlyContinue|?{$_.Name -match 'apex|eaac|jav|sky|qwen'}|Select Name,LastWriteTime|Format-Table -AutoSize|Out-String -Width 300)}catch{W("ERR $($_.Exception.Message)")}

SEC 'reg CI/SecureBoot/SessionMgr'
foreach($p in 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State','HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot','HKLM:\SYSTEM\CurrentControlSet\Control\CI','HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy','HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager','HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'){
 if(Test-Path $p){W("-- $p");try{W(Get-ItemProperty $p|Format-List *|Out-String -Width 300)}catch{W("ERR")}}else{W("-- $p MISSING")}}
W('-- value hunt under Control')
try{W((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control' -Recurse -Depth 3 -ErrorAction SilentlyContinue|%{$k=$_;try{$pp=Get-ItemProperty $k.PSPath -ErrorAction Stop}catch{return};foreach($n in 'CodeIntegrityOptions','TestSigning','EnableVirtualizationBasedSecurity','HypervisorLaunchType','VulnerableDriverBlocklistEnable','HypervisorEnforcedCodeIntegrity'){if($pp.PSObject.Properties.Name -contains $n){"$($k.Name) :: $n = $($pp.$n)"}}}|Sort-Object -Unique|Out-String -Width 300))}catch{W("ERR $($_.Exception.Message)")}
W('-- fltmc filters')
try{W((fltmc.exe filters 2>&1|Out-String -Width 300))}catch{W("ERR")}

SEC 'CI events'
try{W((Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 25 -ErrorAction Stop|%{"$($_.TimeCreated) id=$($_.Id) $($_.LevelDisplayName) :: $($_.Message -replace "`r?`n",' ')"}|Out-String -Width 400))}catch{W("ERR $($_.Exception.Message)")}
try{W((Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Verbose' -MaxEvents 15 -ErrorAction Stop|%{"$($_.TimeCreated) id=$($_.Id) :: $($_.Message -replace "`r?`n",' ')"}|Out-String -Width 400))}catch{W("ERRv $($_.Exception.Message)")}
W("=== END $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') ===")
$sw.Close()
