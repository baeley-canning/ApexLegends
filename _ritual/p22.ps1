# p22 - POST-REBOOT verification: is TESTSIGNING gone, did EAAC stop popping, are drivers still loading?
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p22.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$log22 = Join-Path $PSScriptRoot 'run22.log'
function L($t){ $t | Add-Content -LiteralPath $log22 }
if(-not $adm){
  L ("p22 (unelevated) {0} - raising UAC" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  L 'UAC raised; the elevated p22 writes p22.txt'
  exit
}
"=== p22 POST-BOOT VERIFY $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
W ("  SystemStartOptions = [{0}]" -f $sso)
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
W ("  LastBootUpTime = {0}" -f $boot)
W ("  uptime = {0:N1} min" -f ((New-TimeSpan -Start $boot).TotalMinutes))
if($sso -match 'TESTSIGNING'){ W '  >> NOTE: this kernel was still STARTED with TESTSIGNING (since-boot snapshot, clears only after a reboot)' }
else { W '  >> SystemStartOptions clean: this kernel was started WITHOUT TESTSIGNING' }

# bcdedit needs an elevated token on this host, and mis-parses a bare 'current'.
# Try several forms, keep the first that yields real flag lines, log every attempt for forensics.
W ''
W '-- raw bcdedit attempts:'
$bcdRaw = ''
$bcdSrc = ''
$tries = @(
  @{ n = 'bcdedit /enum {current} /v'; f = { & bcdedit.exe /enum '{current}' /v 2>&1 } },
  @{ n = 'bcdedit /enum all';          f = { & bcdedit.exe /enum all 2>&1 } },
  @{ n = 'cmd /c bcdedit /enum all';   f = { & cmd.exe /c 'bcdedit /enum all' 2>&1 } }
)
foreach($t in $tries){
  $r = @(& $t.f)
  W ('   [{0}] -> {1} line(s): {2}' -f $t.n,$r.Count,(($r -join ' | ') -replace '\s+',' '))
  $j = ($r -join "`n")
  if(-not $bcdSrc -and ($j -match '(?mi)^\s*(testsigning|nointegritychecks)\s+\S+')){ $bcdRaw = $j; $bcdSrc = $t.n }
}
if(-not $bcdSrc){
  $bcdRaw = ('' + $sso)
  $bcdSrc = 'Registry SystemStartOptions (since-boot kernel command line)'
}
W ("  BCD source used = {0}" -f $bcdSrc)

W ''
W '########## GATE MATRIX: BCD flags vs the three known Javelin popup strings ##########'
$names = 'testsigning','nointegritychecks','debug'
$msgs  = 'Test or debug mode must be disabled to start the game.','Device Driver signing integrity checks must be enabled to start the game.','Test or debug mode must be disabled to start the game.'
$gateOpen = @()
for($i=0; $i -lt $names.Count; $i++){
  $n = $names[$i]
  $fm = [regex]::Match($bcdRaw, ('(?mi)^\s*' + $n + '\s+(\S+)'))
  if($fm.Success){ $v = $fm.Groups[1].Value }
  elseif($bcdSrc -like 'Registry*'){
    if([regex]::IsMatch($bcdRaw, ('(?i)\b' + $n + '\b'))){ $v = 'Yes(token)' } else { $v = 'No(no-token)' }
  }
  else { $v = '(absent)' }
  if($v -match '^Yes'){ $gateOpen += $n; $st = 'ON  => GATE OPEN (popup: "' + $msgs[$i] + '")' }
  elseif($v -match '^No'){ $st = 'off => gate satisfied' }
  else { $st = 'unknown => treat as open'; $gateOpen += $n }
  W ('  {0,-18} = {1,-16} {2}' -f $n,$v,$st)
}
W ('  SystemStartOptions(since-boot view) still contains TESTSIGNING: {0}' -f ($sso -match 'TESTSIGNING'))
W '  (registry-sourced rows: a present token proves ON; absence proves OFF only for the kernel already booted)'
W ('  GATES OPEN: {0}' -f $(if($gateOpen.Count){ $gateOpen -join ', ' } else { 'none' }))

W ''
W '########## drivers / services / filters ##########'
$drv = @(Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'apex|eaac|eac|javelin|qwen|kern' })
if($drv){ $drv | ForEach-Object { W ("  DRIVER {0,-18} State={1} Start={2} Path={3}" -f $_.Name,$_.State,$_.StartMode,$_.PathName) } }
else { W '  (no matching Win32_SystemDriver entries)' }
foreach($s in 'eaanticheat','EAAntiCheat','eaanticheat_loader','apexdrv','qwenkern'){
  W ("  sc query {0}: {1}" -f $s, ((((& sc.exe query $s 2>&1) -join ' ~ ') -replace '\s+',' ')))
}
W ("  fltmc filters: {0}" -f ((((& fltmc.exe filters 2>&1) -join ' ~ ') -replace '\s+',' ')))
$present = (@('C:\Windows\System32\drivers\apexdrv.sys','C:\Windows\System32\drivers\eaanticheat.sys','C:\ProgramData\QwenKern\apexdrv.sys') | ForEach-Object { "$_=$(Test-Path -LiteralPath $_)" }) -join ' '
W ("  driver files present: {0}" -f $present)

W ''
W '########## DSE PROOF: will the lab driver still load with testsigning OFF? ##########'
foreach($d in 'kernprobe','eaanticheat','EAAntiCheat'){
  $b = ((& sc.exe start $d 2>&1) -join ' ~ ') -replace '\s+',' '
  $q = ((& sc.exe query $d 2>&1) -join ' ~ ') -replace '\s+',' '
  W ("  sc start {0} -> [{1}]" -f $d, $b)
  W ("    state now: {0}" -f $q)
}
foreach($f in 'C:\Windows\System32\drivers\apexdrv.sys','C:\ProgramData\QwenKern\apexdrv.sys','C:\Windows\System32\drivers\eaanticheat.sys'){
  if(Test-Path -LiteralPath $f){
    $s = Get-AuthenticodeSignature -LiteralPath $f
    $sg = if($s.SignerCertificate){ $s.SignerCertificate.Subject } else { '(none)' }
    W ("  {0} sig={1} signer={2}" -f $f,$s.Status,$sg)
  } else { W ("  {0} MISSING" -f $f) }
}
W '  (577 / 0xc0000428 / BEGINNING_OF_STATUS_DRIVER_ENTRY_SIGNATURE => DSE rejected a self-signed driver)'

W ''
W '########## EAAC / Javelin runtime ##########'
W ("  processes: {0}" -f ((Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'EAAntiCheat|GameService|r5apex|Apex|Javelin|preloader' } | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ','))
W ("  services matching EAAC: {0}" -f ((Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'eaac|anticheat|javelin|apex' } | ForEach-Object { $_.Name + '=' + $_.Status }) -join ','))

W ''
W '########## popup / crash events since boot ##########'
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
foreach($lg in 'Application','System'){
  $ev = @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=$boot} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Application Popup|Application Error|Windows Error Reporting|Service Control Manager' })
  $ev = @($ev | Where-Object { $_.Id -in 15,1000,1001,7031,7034 -or $_.Message -match 'EAAntiCheat|GameService|Apex|Javelin|Security Violation|debug mode' })
  W ("  {0}: {1} relevant events since boot" -f $lg,$ev.Count)
  $ev | Select-Object -First 25 | ForEach-Object { W ("   {0} id={1} src={2} :: {3}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,$_.ProviderName,(($_.Message -replace '\s+',' ').Trim())) }
}
W '-- all Application Popup (id 15) events, last 2 days:'
$ap = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Popup'; StartTime=(Get-Date).AddDays(-2)} -ErrorAction SilentlyContinue)
if(-not $ap){ W '   (none)' } else { $ap | ForEach-Object { W ("   {0} :: {1}" -f $_.TimeCreated.ToString('dd/MM HH:mm:ss'),(($_.Message -replace '\s+',' ').Trim())) } }

W ''
W '########## EAAC log dirs (fresh lines only) ##########'
foreach($root in 'C:\ProgramData\eaanticheat','C:\ProgramData\EAAntiCheat','C:\Users\New User\AppData\Roaming\EA','C:\Program Files\EA Games\Apex'){
  if(-not (Test-Path -LiteralPath $root)){ W "  $root MISSING"; continue }
  $logs = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -lt 20MB -and $_.LastWriteTime -gt $boot -and $_.Extension -match 'log|txt|json|wer' })
  W ("  {0}: {1} files touched since boot" -f $root,$logs.Count)
  foreach($l in $logs){ W ("    {0} {1:N0}B {2}" -f $l.LastWriteTime.ToString('HH:mm:ss'),$l.Length,$l.FullName) }
}
W ''
W '########## VERDICT / NEXT ACTION ##########'
W ('  flags read from: {0}' -f $bcdSrc)
if($sso -match 'TESTSIGNING'){ W '  !! this running kernel was still booted WITH testsigning -> the reboot is still outstanding' }
if($gateOpen.Count){
  W ('  -> GATES STILL OPEN: ' + ($gateOpen -join ', '))
  W '     either bcdedit /set did not stick, no reboot since run21, or bcdedit could not be read here'
  W '     (cross-check the raw bcdedit attempts + SystemStartOptions lines above).'
  W '     re-run run21.cmd (approve UAC), then reboot again before trusting any popup test.'
}
else {
  W '  -> TESTSIGNING gone. Now RELAUNCH Apex (or EAAC GameServiceLauncher) and watch for the popup.'
  W '     popup gone  => fix confirmed: TESTSIGNING was the Javelin kill-flag. Update _ritual/_index.txt.'
  W '     popup now says driver-signing / unacceptable config => a staged driver of ours is being read as tamper:'
  W '        candidate: C:\Windows\System32\drivers\apexdrv.sys (kernprobe, self-signed CN=ApexDrv Dev)'
  W '        option 1: sc stop kernprobe; sc delete kernprobe  (drop our driver entirely)'
  W '        option 2: bcdedit /set testsigning on  (revert) - only if the popup is WORSE without it'
}
W ''
W "-- p22 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
