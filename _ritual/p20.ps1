# p20 - ROOT CAUSE CONFIRMATION: EAAC "Security Violation : Test or debug mode must be disabled to start the game"
# Triggered by SystemStartOptions containing TESTSIGNING. This probe proves provenance + finds what needs testsigning.
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p20.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"=== p20 $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
W 'GOAL: prove TESTSIGNING is the EAAC kill-flag; find the binary that owns the popup text; identify test-signed drivers.'

W ''
W '########## A1 popup-string provenance (STREAMING scan; ASCII + UTF-16LE views) ##########'
$pats = @('Test or debug mode','Security Violation','testsigning','nointegritychecks')
$cands = @(
  'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe',
  'C:\Program Files\EA\AC\EAAntiCheat.GameService.dll',
  'C:\Program Files\EA\AC\EAAntiCheat.Installer.exe',
  'C:\Program Files\EA\AC\preloader_s.dll',
  'C:\Program Files\EA\AC\preloader.dll',
  'C:\Program Files\EA\AC\EAAntiCheatService.exe',
  'C:\Windows\System32\drivers\apexdrv.sys',
  'C:\Windows\System32\drivers\eaanticheat.sys',
  'C:\ProgramData\QwenKern\apexdrv.sys'
)
if(Test-Path 'C:\Program Files\EA Games\Apex'){
  $cands += @(Get-ChildItem 'C:\Program Files\EA Games\Apex' -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'EAAntiCheat|Javelin|Launcher|anticheat|r5apex|start_protected|preload|EasyAnti' -and $_.Length -lt 400MB } |
    Select-Object -First 20 -ExpandProperty FullName)
}
$chunk = 16MB; $over = 512   # 512B overlap so patterns are not lost across chunk seams
function Scan-Bin([string]$path){
  $fi = Get-Item -LiteralPath $path
  W ("  BEGIN {0}  {1:N0} bytes" -f $fi.Name, $fi.Length)
  $fs = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try {
    $found = New-Object 'System.Collections.Hashtable'
    $pos = 0
    while($pos -lt $fi.Length){
      $n = [int][Math]::Min($chunk + $over, [int64]($fi.Length - $pos))
      $buf = New-Object byte[] $n
      $fs.Position = $pos
      $got = $fs.Read($buf,0,$n)
      if($got -le 0){ break }
      $a = [Text.Encoding]::ASCII.GetString($buf,0,$got)
      $w = $a.Replace([string][char]0,'')   # NUL-stripped view => also catches UTF-16LE literals at either offset
      foreach($p in $pats){
        if($found.ContainsKey($p)){ continue }
        foreach($v in @(@($a,'A'),@($w,'W'))){
          $i = $v[0].IndexOf($p,[StringComparison]::OrdinalIgnoreCase)
          if($i -ge 0){
            $st = [Math]::Max(0,$i-140); $ln = [Math]::Min(360,$v[0].Length-$st)
            W ("     HIT[{0}] '{1}' @file+{2}: {3}" -f $v[1],$p,($pos+$i),((($v[0].Substring($st,$ln))) -replace '[\x00-\x1f\x7f]',' ' -replace '\s+',' '))
            $found[$p] = $true
            break
          }
        }
      }
      $pos += $chunk
      Remove-Variable buf,a,w,n,got -ErrorAction SilentlyContinue
    }
    if($found.Count -eq 0){ W '     (no pattern hits in this file)' }
  } catch { W ("     SCAN ERROR {0}" -f $_.Exception.Message) }
  finally { if($fs){ $fs.Dispose() } }
}
foreach($f in $cands){
  if(Test-Path -LiteralPath $f){ Scan-Bin $f } else { W ("  BEGIN {0} MISSING" -f (Split-Path $f -Leaf)) }
}

W ''
W '########## C payload / staging locations ##########'
foreach($d in 'C:\ProgramData\eaanticheat','C:\ProgramData\QwenKern','C:\Program Files\EA\AC','C:\ProgramData\EAAntiCheat','C:\ProgramData\EA AntiCheat'){
  if(Test-Path -LiteralPath $d){
    W "-- ${d}:"
    Get-ChildItem -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { W ("   {0,12} {1} {2}" -f $_.Length, $_.LastWriteTime.ToString('dd/MM/yy HH:mm'), $_.FullName) }
  } else { W "-- $d MISSING" }
}
W '-- *.sys reachable from EA/AC, Apex, temp staging:'
foreach($d in 'C:\Program Files\EA\AC','C:\Program Files\EA Games\Apex',$env:TEMP,'C:\Windows\Temp'){
  if(Test-Path $d){ Get-ChildItem -LiteralPath $d -Recurse -Force -File -Filter '*.sys' -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { W ("   SYS {0,12} {1}" -f $_.Length, $_.FullName) } }
}
W '-- temp entries matching ea/javelin/ac:'
Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ea|javelin|_ac' } | ForEach-Object { W ("   TEMP {0} {1}" -f $_.LastWriteTime.ToString('dd/MM/yy HH:mm'), $_.Name) }

W ''
W '########## D service / filter state (incl. Instances values) ##########'
foreach($n in 'EAAntiCheat','eaanticheat','EAAntiCheatService'){
  W ("  sc qc {0}: {1}" -f $n, (((& sc.exe qc $n 2>&1) -join ' ~ ') -replace '\s+',' '))
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
  if(Test-Path $k){
    $p = Get-ItemProperty $k
    W ("  KEY {0} Type={1} Start={2} Tag={3} SupportedFeatures={4} Img={5}" -f $n,$p.Type,$p.Start,$p.Tag,$p.SupportedFeatures,$p.ImagePath)
    if(Test-Path "$k\Instances"){
      (Get-ItemProperty "$k\Instances").PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { W ("     Instances.{0} = {1}" -f $_.Name,$_.Value) }
      Get-ChildItem "$k\Instances" -ErrorAction SilentlyContinue | ForEach-Object { W ("     SUBKEY {0}" -f $_.PSChildName) }
    } else { W '     Instances MISSING' }
  }
}
W ("  fltmc filters: {0}" -f (((& fltmc.exe filters 2>&1) -join ' | ') -replace '\s+',' '))

W ''
W '########## E boot / CI / SecureBoot state ##########'
$cs = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control'
W ("  SystemStartOptions = {0}" -f $cs.SystemStartOptions)
foreach($k in 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State','HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy','HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config','HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'){
  if(Test-Path $k){ W "  [$k]"; (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { W ("     {0} = {1}" -f $_.Name, $_.Value) } } else { W "  [$k] MISSING" }
}
W ("  bcdedit /enum {{current}}: {0}" -f (((& bcdedit.exe /enum '{current}' 2>&1) -join ' ~ ') -replace '\s+',' '))
try { W ("  Confirm-SecureBootUEFI = {0}" -f (Confirm-SecureBootUEFI)) } catch { W ("  Confirm-SecureBootUEFI failed: {0}" -f $_.Exception.Message) }

W ''
W '########## F cert stores: non-Microsoft / test cert candidates ##########'
$msrx = 'Microsoft|DigiCert|Baltimore|GlobalSign|Sectigo|COMODO|USERTrust|AAA Cert|Entrust|Go Daddy|VeriSign|Thawte|Starfield|Certum|ISRG|Amazon|Google Trust|QuoVadis|SwissSign|T-TeleSec|D-TRUST|Buypass|Hongkong|SecureTrust|XRamp|AffirmTrust|Network Solutions|SSL.com|E-Tugra|HARICA|Certainly|Certigna|GTS|Actalis|IdenTrust|TWCA'
foreach($st in 'Cert:\LocalMachine\Root','Cert:\LocalMachine\TrustedPublisher','Cert:\LocalMachine\TrustedPeople','Cert:\LocalMachine\CA'){
  $all = @(Get-ChildItem $st -ErrorAction SilentlyContinue)
  $odd = @($all | Where-Object { $_.Subject -notmatch $msrx })
  W ("  {0}: total={1} nonMS={2}" -f $st,$all.Count,$odd.Count)
  $odd | Select-Object -First 25 | ForEach-Object { W ("     {0} | {1} | exp {2}" -f $_.Thumbprint.Substring(0,8), $_.Subject, $_.NotAfter) }
}

W ''
W '########## G fix attempt (needs admin) ##########'
W ("  bcdedit /set testsigning off -> {0}" -f (((& bcdedit.exe /set testsigning off 2>&1) -join ' ~ ') -replace '\s+',' '))
W ("  bcdedit /set nointegritychecks off -> {0}" -f (((& bcdedit.exe /set nointegritychecks off 2>&1) -join ' ~ ') -replace '\s+',' '))
W ("  bcdedit /set debug off -> {0}" -f (((& bcdedit.exe /set debug off 2>&1) -join ' ~ ') -replace '\s+',' '))
W ("  AFTER: bcdedit /enum: {0}" -f (((& bcdedit.exe /enum 2>&1) -join ' ~ ') -replace '\s+',' '))
W '  NOTE: testsigning change only takes effect after REBOOT.'

W ''
W '########## B driver inventory (added <=120d) + signature status ##########'

Get-ChildItem 'C:\Windows\System32\drivers' -Force -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-120) } | Sort-Object LastWriteTime | ForEach-Object {
    $s = Get-AuthenticodeSignature -LiteralPath $_.FullName -ErrorAction SilentlyContinue
    $sc = $s.SignerCertificate
    $self = if($sc){ ($sc.Subject -eq $sc.Issuer) } else { $null }
    W ("  {0,10} {1} {2,-11} selfsigned={3,-5} signer={4}" -f $_.Length, $_.LastWriteTime.ToString('dd/MM/yy HH:mm'), $s.Status, $self, $(if($sc){$sc.Subject}else{'-'}))
  }
W '-- named files (SIG = authenticode; selfsigned=True means needs TESTSIGNING unless cross-signed):'
foreach($f in 'C:\Windows\System32\drivers\eaanticheat.sys','C:\Windows\System32\drivers\apexdrv.sys','C:\Windows\System32\drivers\qwenkern.sys','C:\Windows\System32\drivers\kernprobe.sys','C:\Windows\System32\drivers\zzprobe.sys','C:\Windows\System32\drivers\gdrv3.sys','C:\ProgramData\QwenKern\apexdrv.sys'){
  if(Test-Path -LiteralPath $f){
    $s = Get-AuthenticodeSignature -LiteralPath $f; $sc = $s.SignerCertificate
    W ("  SIG {0} :: {1} | selfsigned={2} | subj={3} | issuer={4}" -f $f, $s.Status, $(if($sc){($sc.Subject -eq $sc.Issuer)}else{'-'}), $(if($sc){$sc.Subject}else{'-'}), $(if($sc){$sc.Issuer}else{'-'}))
  } else { W "  SIG $f MISSING" }
}

W ''
W '########## A2 same streaming scan on earlier p13 string dumps (up to 150MB each) ##########'
foreach($f in 'p13_strall_launcher.txt','p13_strall_launcherdll.txt','p13_strall_gameservice.txt','p13_strall_gameservicedll.txt'){
  $p = Join-Path $PSScriptRoot $f
  if(Test-Path -LiteralPath $p){ Scan-Bin $p } else { W "  DUMP $f MISSING" }
}

W ''
W '########## A3 EAAC + EA logs mentioning test/debug/violation ##########'
foreach($root in 'C:\Users\New User\AppData\Roaming\EA','C:\ProgramData\eaanticheat','C:\Program Files\EA\AC'){
  if(-not (Test-Path -LiteralPath $root)){ W "  LOGROOT $root MISSING"; continue }
  $logs = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 25MB })
  W ("  {0}: {1} files" -f $root, $logs.Count)
  foreach($l in $logs){
    $m = @(Select-String -LiteralPath $l.FullName -Pattern 'debug mode|testsigning|test signing|Security Violation|violation|57a6|1077|integrity' -ErrorAction SilentlyContinue)
    if($m){ W ("   -- {0} matches={1}" -f $l.FullName, $m.Count); $m | Select-Object -Last 6 | ForEach-Object { W ("      L{0}: {1}" -f $_.LineNumber, (($_.Line -replace '\s+',' ').Trim())) } }
  }
}

"=== END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Add-Content -LiteralPath $o
W '-- p20 done'
