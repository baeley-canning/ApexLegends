$ErrorActionPreference='Continue'
$out='c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p13_dirs3.txt'
$sw=New-Object System.IO.StreamWriter($out,$false,(New-Object System.Text.UTF8Encoding($true)))
function W($s){$sw.WriteLine([string]$s);$sw.Flush()}
function SEC($s){W("");W("########## $s ##########")}
W("=== p13 dirs3 certs/cfg/logs $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') ===")

SEC 'EA Application/System events 3d'
try{W((Get-WinEvent -FilterHashtable @{LogName='Application','System';StartTime=(Get-Date).AddDays(-3)} -ErrorAction Stop|?{$_.Message -match 'apex|eaanticheat|javelin|skyfall|AntiCheat'}|Select -First 40|%{"$($_.TimeCreated) [$($_.LogName)] $($_.ProviderName) id=$($_.Id) :: $($_.Message -replace "`r?`n",' ')"}|Out-String -Width 400))}catch{W("ERR $($_.Exception.Message)")}

SEC 'logs eaanticheat tree'
try{W((Get-ChildItem 'C:\ProgramData\eaanticheat' -Recurse -Force -ErrorAction SilentlyContinue|Select FullName,Length,LastWriteTime|Format-Table -AutoSize|Out-String -Width 300))}catch{W("ERR")}
SEC 'EA Desktop recent files'
try{W((Get-ChildItem 'C:\ProgramData\EA Desktop' -Recurse -Force -ErrorAction SilentlyContinue|Sort LastWriteTime -Desc|Select -First 20 FullName,Length,LastWriteTime|Format-Table -AutoSize|Out-String -Width 300))}catch{W("ERR")}
SEC 'EALauncher.log tail 40'
try{W((Get-Content 'C:\ProgramData\EA Desktop\Logs\EALauncher.log' -Tail 40 -ErrorAction Stop|Out-String -Width 400))}catch{W("ERR $($_.Exception.Message)")}
SEC 'trust-cert / blocked lines across EA logs'
try{W((Select-String -Path 'C:\ProgramData\EA Desktop\Logs\*.log' -Pattern 'trust cert|TrustCert|blocked trust|result\[|skyfall|Skipping' -ErrorAction SilentlyContinue|Select -Last 50|%{"$($_.Filename):$($_.LineNumber): $($_.Line)"}|Out-String -Width 400))}catch{W("ERR $($_.Exception.Message)")}

SEC 'EA AC file signatures'
try{foreach($p in 'C:\Program Files\EA Games\Apex\EAAntiCheat.cfg','C:\Program Files\EA\AC\EAAntiCheat.GameService.exe','C:\Program Files\EA Games\Apex\EAAntiCheat.GameServiceLauncher.exe','C:\Program Files\EA\AC\EAAntiCheat.Installer.exe'){
 if(Test-Path $p){$s=Get-AuthenticodeSignature $p;W("$p`n  Status=$($s.Status) $($s.StatusMessage)`n  Signer=$($s.SignerCertificate.Subject)`n  Issuer=$($s.SignerCertificate.Issuer) NotAfter=$($s.SignerCertificate.NotAfter)")}else{W("MISSING $p")}}}catch{W("ERR $($_.Exception.Message)")}

SEC 'root store: count + recent + suspects'
try{
 $r=Get-ChildItem Cert:\LocalMachine\Root
 W("Root count=$($r.Count)")
 W('-- roots issued/created since 2026-09-01 (store-recent or self-signed new CA)')
 foreach($x in ($r|?{$_.NotBefore -ge (Get-Date '2026-09-01')})){W("  $($x.NotBefore) -> $($x.NotAfter) [$($x.Thumbprint)] $($x.Subject) rawLen=$($x.RawData.Length)")}
 W('-- suspect matches')
 foreach($x in ($r|?{$_.Subject -match 'AAA Certificate|DigiCert Trusted G4|ApexDrv|Qwen|Sectigo|USERTrust|Dev'})){$d=$null;try{$d=$x.Export('Der')}catch{};W("  [$($x.Thumbprint)] $($x.Subject) notAfter=$($x.NotAfter) rawLen=$($x.RawData.Length) derLen=$(if($d){$d.Length}else{'EXPORT-FAIL'})")}
 W('-- all LocalMachine Root subjects')
 foreach($x in $r){W("  $($x.NotBefore.ToString('yyyy-MM-dd')) [$($x.Thumbprint)] $($x.Subject)")}
}catch{W("ERR $($_.Exception.Message)")}

SEC 'EAAntiCheat.cfg: cert blob scan'
$cfg='C:\Program Files\EA Games\Apex\EAAntiCheat.cfg'
try{
 $b=[IO.File]::ReadAllBytes($cfg)
 W("len=$($b.Length) sha256=$((Get-FileHash $cfg -Algorithm SHA256).Hash)")
 $ascii=[Text.Encoding]::ASCII.GetString($b)
 foreach($k in 'AAA Certificate','DigiCert','Certificate Services','Qwen','EA AntiCheat','ApexDrv','skyfall'){W("ascii contains '$k': $($ascii.Contains($k))")}
 $i=0;$m=0
 while($i -lt $b.Length-4){
   if($b[$i] -eq 0x30 -and $b[$i+1] -eq 0x82){
     $len=$b[$i+2]*256+$b[$i+3]
     if($len -gt 200 -and ($i+4+$len) -le $b.Length){
       $seg=New-Object byte[] $len
       [Array]::Copy($b,$i+4,$seg,0,$len)
       $m++
       try{ $c=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($seg); W("blob@$i len=$len OK subj=$($c.Subject) iss=$($c.Issuer) notAfter=$($c.NotAfter)") }
       catch{ W("blob@$i len=$len DECODE-FAIL: $($_.Exception.Message)") }
       $i+=4+$len; continue
     }
   }
   $i++
 }
 W("scan done, $m candidate blobs")
}catch{W("ERR $($_.Exception.Message)")}

SEC 'EA AC dir listing'
try{W((Get-ChildItem 'C:\Program Files\EA\AC' -Force|Select Name,Length,LastWriteTime|Format-Table -AutoSize|Out-String -Width 300))}catch{W("ERR")}
SEC 'tools'
try{W((Get-Command openssl,certutil -ErrorAction SilentlyContinue|Select Name,Source|Format-Table -AutoSize|Out-String))}catch{W("ERR")}
W("=== END $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') ===")
$sw.Close()
