# p20b - follow-up to p20: format-template patterns, game exe, service/cert/WER/event forensics
# Context: p20 proved only GameService.exe owns 'Security Violation'; body text is not a raw literal in any EAAS file.
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p20b.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"=== p20b $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o

W ''
W '########## 1 fine-grained pattern scan of GameService.exe (format-template hunt) ##########'
$pats = @('debug mode','must be disabled','or debug','to start the game','262147','TESTSIGNING','testsigning',
          'SystemStartOptions','BcdEdit','Developer Mode','TestMode','Test Signing','integritychecks','debugging mode')
$fs = $null
try {
  $f = 'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe'
  $fi = Get-Item -LiteralPath $f
  W ("  target={0} size={1:N0}" -f $f, $fi.Length)
  $fs = [IO.File]::Open($f,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  $chunk = 8MB; $over = 512; $pos = 0; $found = New-Object 'System.Collections.Hashtable'
  while($pos -lt $fi.Length){
    $n = [int][Math]::Min($chunk + $over, [int64]($fi.Length - $pos))
    $buf = New-Object byte[] $n
    $fs.Position = $pos; $got = $fs.Read($buf,0,$n)
    if($got -le 0){ break }
    $a = [Text.Encoding]::ASCII.GetString($buf,0,$got)
    $w = $a.Replace([string][char]0,'')
    foreach($p in $pats){
      if($found.ContainsKey($p)){ continue }
      foreach($v in @(@($a,'A'),@($w,'W'))){
        $i = $v[0].IndexOf($p,[StringComparison]::OrdinalIgnoreCase)
        if($i -ge 0){
          $st = [Math]::Max(0,$i-120); $ln = [Math]::Min(300,$v[0].Length-$st)
          W ("     HIT[{0}] '{1}' @{2}: {3}" -f $v[1],$p,($pos+$i),((($v[0].Substring($st,$ln))) -replace '[\x00-\x1f\x7f]',' ' -replace '\s+',' '))
          $found[$p] = $true; break
        }
      }
    }
    $pos += $chunk
  }
  W ("  total patterns matched: {0}" -f $found.Count)
} catch { W ("  ERROR {0}" -f $_.Exception.Message) } finally { if($fs){ $fs.Dispose() } }

W ''
W '########## 2 EAAntiCheat.cfg (full) + Apex dir listing ##########'
$cfg = 'C:\Program Files\EA Games\Apex\EAAntiCheat.cfg'
if(Test-Path -LiteralPath $cfg){ W ("-- {0}" -f $cfg); Get-Content -LiteralPath $cfg -ErrorAction SilentlyContinue | ForEach-Object { W ("   {0}" -f $_) } }
foreach($d in 'C:\Program Files\EA Games\Apex','C:\Program Files\EA\AC'){
  if(Test-Path -LiteralPath $d){
    W "-- LIST ${d}:"
    Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
      W ("   {0,12} {1} {2}" -f $(if($_.PSIsContainer){'<DIR>'}else{$_.Length}), $_.LastWriteTime.ToString('dd/MM/yy HH:mm'), $_.Name) }
  } else { W "-- ${d} MISSING" }
}

W ''
W '########## 3 game exe scan (r5apex / start_protected) ##########'
$game = @()
foreach($d in 'C:\Program Files\EA Games\Apex','C:\Program Files (x86)\Steam\steamapps\common\Apex Legends','C:\Program Files\EA Games'){
  if(Test-Path -LiteralPath $d){
    $game += @(Get-ChildItem -LiteralPath $d -Force -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '\.(exe|dll)$' -and $_.Name -match 'r5apex|start_protected|Javelin|EAAntiCheat|apex' } | Select-Object -Unique -ExpandProperty FullName)
  }
}
$game = $game | Select-Object -Unique
W ("  game exe/dll candidates: {0}" -f ($game -join ' | '))
foreach($f in $game){
  if($f -like '*GameService*' -or $f -like '*Installer*'){ continue }   # already scanned in p20
  $fi = Get-Item -LiteralPath $f
  if($fi.Length -gt 500MB){ W ("  SKIP {0} too big" -f $f); continue }
  $fs = $null
  try {
    $fs = [IO.File]::Open($f,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $chunk = 8MB; $over = 512; $pos = 0; $hits = 0
    while($pos -lt $fi.Length){
      $n = [int][Math]::Min($chunk + $over, [int64]($fi.Length - $pos))
      $buf = New-Object byte[] $n
      $fs.Position = $pos; $got = $fs.Read($buf,0,$n)
      if($got -le 0){ break }
      $a = [Text.Encoding]::ASCII.GetString($buf,0,$got); $w = $a.Replace([string][char]0,'')
      foreach($p in $pats){
        $i = $a.IndexOf($p,[StringComparison]::OrdinalIgnoreCase)
        $view = 'A'
        if($i -lt 0){ $i = $w.IndexOf($p,[StringComparison]::OrdinalIgnoreCase); $view = 'W' }
        if($i -ge 0){
          $src = $(if($view -eq 'A'){$a}else{$w})
          $st = [Math]::Max(0,$i-110); $ln = [Math]::Min(280,$src.Length-$st)
          W ("  {0} HIT[{1}] '{2}' @{3}: {4}" -f $fi.Name,$view,$p,($pos+$i),((($src.Substring($st,$ln))) -replace '[\x00-\x1f\x7f]',' ' -replace '\s+',' '))
          $hits++
        }
        if($hits -gt 40){ break }
      }
      $pos += $chunk
    }
    W ("  {0}: done, hits={1}" -f $fi.Name,$hits)
  } catch { W ("  {0} ERROR {1}" -f $f,$_.Exception.Message) } finally { if($fs){ $fs.Dispose() } }
}

W ''
W '########## 4 service / driver registry + runtime state ##########'
foreach($s in 'eaanticheat','EAAntiCheat','EAAntiCheatService','apexdrv','qwenkern','kernprobe','zzprobe'){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
  if(Test-Path -LiteralPath $k){
    $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    W ("  SVC {0,-18} Start={1} Type={2} Image=[{3}]" -f $s,$p.Start,$p.Type,$p.ImagePath)
    $inst = @(Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName)
    W ("      subkeys: {0}" -f $(if($inst){$inst -join ','}else{'(none)'}))
  } else { W "  SVC $s MISSING" }
}
W '-- sc query eaanticheat / apexdrv:'
W ((((& sc.exe query eaanticheat 2>&1) -join ' ~ ') -replace '\s+',' '))
W ((((& sc.exe query apexdrv 2>&1) -join ' ~ ') -replace '\s+',' '))
W '-- Services / Class keys matching eaac-ish names:'
W ("  Services: {0}" -f ((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'eaanticheat|apexdrv|qwenkern|javelin|probe' } | Select-Object -ExpandProperty PSChildName) -join ','))
W ("  Control\Class: {0}" -f ((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'eaanticheat|apexdrv|javelin' } | Select-Object -ExpandProperty PSChildName) -join ','))

W ''
W '########## 5 flags: BCD / SystemStartOptions / DevMode / SecureBoot / VBS / Verifier ##########'
W ("  SystemStartOptions = [{0}]" -f ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions))
W ("  bcdedit /enum current: {0}" -f ((((& bcdedit.exe /enum '{current}' 2>&1) -join ' ~ ') -replace '\s+',' ')))
foreach($n in 'AllowDevelopmentWithoutDevLicense','AllowAllTrustedApps'){
  W ("  AppModelUnlock.{0} = [{1}]" -f $n, ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).$n))
}
try { W ("  SecureBoot = {0}" -f (Confirm-SecureBootUEFI)) } catch { W ("  SecureBoot query failed: {0}" -f $_.Exception.Message) }
W ("  verifier: {0}" -f ((((& verifier.exe /querysettings 2>&1) -join ' ~ ') -replace '\s+',' ')))
W ("  DeviceGuard: {0}" -f ((((Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction SilentlyContinue | Select-Object VirtualizationBasedSecurityStatus,SecurityServicesRunning,SecurityServicesConfigured | Format-List | Out-String)) -replace '\s+',' ')))
if(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'){
  W ("  HVCI key present; Enabled = {0}" -f ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue).Enabled))
} else { W '  HVCI scenario key MISSING' }

W ''
W '########## 6 WER reports touching EAAC / GameService / apex ##########'
foreach($root in 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive','C:\ProgramData\Microsoft\Windows\WER\ReportQueue'){
  if(-not (Test-Path -LiteralPath $root)){ W "  $root MISSING"; continue }
  $reps = @(Get-ChildItem -LiteralPath $root -Recurse -Force -Filter 'Report.wer' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-20) })
  W ("  {0}: {1} reports (last 20d)" -f $root,$reps.Count)
  foreach($r in $reps){
    $t = @(Get-Content -LiteralPath $r.FullName -ErrorAction SilentlyContinue -TotalCount 80)
    $app = (($t | Where-Object { $_ -match '^AppName=' }) -join ' ')
    if($app -match 'EAAntiCheat|GameService|r5apex|Apex|Javelin|start_protected|Installer'){
      W ("  -- {0} :: {1}" -f $r.Directory.Name,$app)
      $t | Where-Object { $_ -match '^(EventType|AppPath|ModName|ExceptionCode|Sig\[[0-9]+\]\.(Name|Value)|DynamicSig)' } | Select-Object -First 16 | ForEach-Object { W ("       {0}" -f $_) }
    }
  }
}

W ''
W '########## 7 lab driver signature audit (what actually NEEDS testsigning) ##########'
foreach($f in (Get-ChildItem 'C:\Windows\System32\drivers' -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'apexdrv|qwenkern|kernprobe|zzprobe|eaanticheat|gdrv|vgk|iqvw|eastanti' })){
  $s = Get-AuthenticodeSignature -LiteralPath $f.FullName -ErrorAction SilentlyContinue; $sc = $s.SignerCertificate
  W ("  SIG {0,10} {1} {2,-12} self={3,-5} subj={4} | issuer={5}" -f $f.Length,$f.LastWriteTime.ToString('dd/MM/yy'),$s.Status,$(if($sc){($sc.Subject -eq $sc.Issuer)}else{'-'}),$(if($sc){$sc.Subject}else{'-'}),$(if($sc){$sc.Issuer}else{'-'}))
}
W '-- local certs in Root/TrustedPublisher matching lab names:'
foreach($st in 'Cert:\LocalMachine\Root','Cert:\LocalMachine\TrustedPublisher'){
  $c = @(Get-ChildItem $st -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'apex|qwen|kern|probe|test|develop' -or $_.FriendlyName -match 'apex|qwen|kern|probe' })
  W ("  {0}: {1}" -f $st,$(if($c){($c | ForEach-Object { $_.Subject }) -join ' ;; '}else{'(no matching certs)'}))
}

W ''
W '########## 8 event forensics (popup / service death / WER) ##########'
foreach($lg in 'Application','System'){
  $ev = @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=(Get-Date).AddDays(-3)} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Application Popup|Application Error|Windows Error Reporting|Service Control Manager' })
  $ev = @($ev | Where-Object { $_.Id -in 15,1000,1001,7031,7034,7045 -or $_.Message -match 'EAAntiCheat|GameService|Apex|Javelin|apexdrv|anticheat|Security Violation|test or debug' })
  W ("  {0}: {1} matching events" -f $lg,$ev.Count)
  $ev | Select-Object -First 45 | ForEach-Object { W ("   {0} id={1} src={2} :: {3}" -f $_.TimeCreated.ToString('dd/MM HH:mm:ss'),$_.Id,$_.ProviderName,(($_.Message -replace '\s+',' ').Trim())) }
}

W ''
W '########## 9 EAAC / EA logs: debug|testsign|violation|262147 ##########'
foreach($root in 'C:\Users\New User\AppData\Roaming\EA','C:\ProgramData\eaanticheat','C:\ProgramData\EAAntiCheat','C:\Program Files\EA\AC','C:\Program Files\EA Games\Apex'){
  if(-not (Test-Path -LiteralPath $root)){ W "  LOGROOT $root MISSING"; continue }
  $logs = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 30MB -and $_.Extension -match 'log|txt|json|cfg|ini|wer|xml' })
  W ("  {0}: {1} candidate log files" -f $root,$logs.Count)
  foreach($l in $logs){
    $m = @(Select-String -LiteralPath $l.FullName -Pattern 'debug mode|testsigning|test signing|Security Violation|262147|violation|integrity|developer mode' -ErrorAction SilentlyContinue)
    if($m){ W ("   -- {0} matches={1}" -f $l.FullName,$m.Count); $m | Select-Object -Last 6 | ForEach-Object { W ("      L{0}: {1}" -f $_.LineNumber,(($_.Line -replace '\s+',' ').Trim())) } }
  }
}

W ''
W '########## 10 dump corpus + setupapi: apex/eaac install + popup-string history ##########'
$dumps = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^p\d+.*\.(txt|log|json|csv)$' -and $_.Length -lt 40MB })
W ("  scanning {0} prior dumps/logs in _ritual" -f $dumps.Count)
foreach($d in $dumps){
  $m = @(Select-String -LiteralPath $d.FullName -Pattern 'must be disabled|Test or debug|262147|testsigning|TestMode|SystemStartOptions|QwenKern|apexdrv|eaanticheat|Security Violation' -ErrorAction SilentlyContinue)
  if($m){ W ("  -- {0} hits={1}" -f $d.Name,$m.Count); $m | Select-Object -First 8 | ForEach-Object { W ("     L{0}: {1}" -f $_.LineNumber,(($_.Line -replace '\s+',' ').Trim())) } }
}
foreach($lg in 'C:\Windows\INF\setupapi.dev.log'){
  if(Test-Path -LiteralPath $lg){
    $m = @(Select-String -LiteralPath $lg -Pattern 'apexdrv|eaanticheat|EAAntiCheat|qwenkern|kernprobe' -ErrorAction SilentlyContinue)
    W ("  -- {0} hits={1}" -f $lg,$m.Count); $m | Select-Object -Last 12 | ForEach-Object { W ("     L{0}: {1}" -f $_.LineNumber,(($_.Line -replace '\s+',' ').Trim())) }
  } else { W "  -- $lg MISSING" }
}
W '-- full popup event (Application Popup id 15) raw XML:'
foreach($e2 in @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Popup'; StartTime=(Get-Date).AddDays(-4)} -ErrorAction SilentlyContinue | Select-Object -First 5)){
  W ("  == {0}" -f $e2.TimeCreated.ToString('dd/MM HH:mm:ss'))
  W (($e2.Message -replace '\s+',' ').Trim())
}

"-- p20b END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --" | Add-Content -LiteralPath $o
