# p27 - ESP-IN-GAME, STAGE 1: JAVELIN GATE TEST.
# Decision this run makes: may TESTSIGNING stay ON while the game runs?
#   popup    -> TESTSIGNING must go off (then apexdrv needs the cat-store fix = stage 4)
#   no popup -> apexdrv stays RUNNING and B3 (kernel inject) is usable right away
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p27_gate.ps1 -Launch [-WaitSec 300]
# Writes: _ritual\p27_gate.txt   (streams while it waits)
param([switch]$Launch, [int]$WaitSec = 300)
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p27_gate.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"=== p27 GATE TEST $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') user=$env:USERNAME admin=$adm host=$env:COMPUTERNAME launch=$Launch ===" | Set-Content -LiteralPath $o

# Javelin popup strings: the three BCD gates + the downstream "unacceptable" stage.
# The literal "Security Violation" lives in EAAntiCheat.GameService.exe (UTF-16), so the
# event-log MESSAGE is matched, not a file grep.
$RX = 'Security Violation|must be disabled to start|signing integrity checks must be enabled|unacceptable configuration'
# p31b FIX: ProcessName NEVER carries ".exe" (PowerShell strips it), so a
# "$GAME -contains $_.ProcessName" test against '*.exe' entries could never match -> every
# alive= row and firstPid stayed 0 (false negative) even with the game running. Extensionless now.
$GAME = @('r5apex_dx12','r5apex','baeleys')
$EAD  = 'C:\Program Files\Electronic Arts\EA Desktop\13.813.1.6327-1792985412\EA Desktop\EADesktop.exe'

function Get-Popup([datetime]$since){
  $hits = @()
  foreach($lg in 'Application','System'){
    $ev = @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=$since} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match $RX -or ($_.ProviderName -match 'Application Popup' -and $_.Id -eq 26) })
    foreach($e in $ev){
      $msg = (($e.Message) -replace '\s+',' ').Trim()
      if(-not $msg){ $msg = (($e.Properties | ForEach-Object { [string]$_.Value }) -join ' | ') }
      $hits += ('{0} {1} id={2} src={3} :: {4}' -f $e.TimeCreated.ToString('HH:mm:ss'),$lg,$e.Id,$e.ProviderName,$msg)
    }
  }
  return $hits
}
function GameProc(){
  Get-Process -ErrorAction SilentlyContinue | Where-Object { $GAME -contains $_.ProcessName } |
    Sort-Object { $_.ProcessName -ne 'r5apex_dx12' } | Select-Object -First 1
}

W ''
W '########## A: pre-flight state ##########'
$sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
W ("  SystemStartOptions = [{0}]" -f $sso)
W ("  booted             = {0}  (uptime {1:N0} min)" -f $boot, ((New-TimeSpan -Start $boot).TotalMinutes))
if($sso -match 'TESTSIGNING'){ W '  >> this KERNEL was booted WITH testsigning: a popup now is the expected test-mode gate (not our driver)' }
else { W '  >> kernel booted WITHOUT testsigning: apexdrv should NOT load (577) and no test-mode popup is expected' }
foreach($s in 'apexdrv','apexdrv_cat','kernprobe','eaanticheat','EAAntiCheatService'){
  $st = ((& sc.exe query $s 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() })
  W ("  svc {0,-20} {1}" -f $s, ($st -join ' / '))
}
$ours = @(Get-ChildItem 'C:\Windows\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}' -Filter 'apexdrv*.cat' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + '@' + $_.LastWriteTime.ToString('MM-dd HH:mm') })
W ("  our cats in the system catalog store: {0}" -f (($ours -join ', ')))
W ("  game processes before launch: {0}" -f ((Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|baeleys|EAAntiCheat|eaanticheat' } | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ','))
$base = Get-Popup (Get-Date).AddHours(-6)
W ("  popups in the last 6 h (baseline): {0}" -f $base.Count)
$base | ForEach-Object { W ('    PRE ' + $_) }

W ''
W '########## B: launch ##########'
$t0 = Get-Date
if(-not $Launch){
  W '  (-Launch not given: waiting for a game the operator starts himself)'
} else {
  $ea = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'EADesktop|EABackgroundService' }
  if(-not $ea){
    if(Test-Path -LiteralPath $EAD){
      W ("  EA app not running -> starting {0}" -f $EAD)
      Start-Process -FilePath $EAD | Out-Null
      for($i=0; $i -lt 12 -and -not (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'EADesktop' }); $i++){ Start-Sleep -Seconds 5 }
      Start-Sleep -Seconds 10
    } else { W ("  !! EA app exe not found at {0}" -f $EAD) }
  } else { W ("  EA app already running: {0}" -f (($ea | ForEach-Object { $_.ProcessName }) -join ',')) }

  $exe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
  if(Test-Path -LiteralPath $exe){ W ("  launching {0}" -f $exe); Start-Process -FilePath $exe | Out-Null }
  else { W ("  !! game exe missing: {0}" -f $exe) }
}

W ''
W '########## C: watch (popup / survival / AC service) ##########'
$firstPid = 0; $sawPopup = $false; $deadAfterUp = $false; $popupLines = @()
$elapsed = 0
while($elapsed -lt $WaitSec){
  Start-Sleep -Seconds 5; $elapsed += 5
  $p = GameProc
  if($p -and $firstPid -eq 0){ $firstPid = $p.Id; W ("  t+{0,3}s GAME UP pid={1} name={2} ws={3} MB" -f $elapsed,$p.Id,$p.ProcessName,[int]($p.WorkingSet64/1MB)) }
  if($firstPid -ne 0 -and -not $p){ W ("  t+{0,3}s GAME EXITED (it was pid {1})" -f $elapsed,$firstPid); $deadAfterUp = $true }
  $new = @(Get-Popup $t0 | Where-Object { $base -notcontains $_ })
  if($new.Count -and -not $sawPopup){
    $sawPopup = $true; $popupLines = $new
    W ("  t+{0,3}s *** POPUP ***" -f $elapsed)
    $new | ForEach-Object { W ('     ' + $_) }
  }
  if(($elapsed % 30) -eq 0){
    $svc = (Get-Service EAAntiCheatService -ErrorAction SilentlyContinue).Status
    $win = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'AntiCheat|Apex|Security|Javelin' } | ForEach-Object { $_.ProcessName + ':' + $_.MainWindowTitle })
    $alive = 'no'; if($p){ $alive = 'yes' }
    W ("  t+{0,3}s alive={1} EAAntiCheatService={2} windows=[{3}]" -f $elapsed,$alive,$svc,($win -join ' | '))
  }
  if($deadAfterUp -and $elapsed -gt 60){ break }
}

W ''
W '########## D: EAAC / driver state after the test ##########'
W ("  processes: {0}" -f ((Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|baeleys|EAAntiCheat|eaanticheat' } | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ','))
foreach($s in 'eaanticheat','EAAntiCheatService','apexdrv'){
  W ("  sc query {0}: {1}" -f $s, (((& sc.exe query $s 2>&1) -join ' ~ ') -replace '\s+',' '))
}
$ev = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=$t0} -ErrorAction SilentlyContinue)
W ("  CodeIntegrity events since launch: {0}" -f $ev.Count)
$ev | Select-Object -First 8 | ForEach-Object { W ("   {0} id={1} :: {2}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,(($_.Message -split "`r`n")[0])) }

W ''
W '########## VERDICT ##########'
if($sawPopup){
  W '  GATE OPEN -> Javelin raised:'
  $popupLines | ForEach-Object { W ('    ' + $_) }
  $joined = ($popupLines -join ' ')
  if($joined -match 'must be disabled to start|debug mode'){
    W '  => "Test or debug mode must be disabled" = TESTSIGNING is the kill flag.'
    W '     NEXT: bcdedit /set {current} testsigning off ; reboot ; then STAGE 4 (cat store) so apexdrv still loads.'
  } elseif($joined -match 'integrity checks'){ W '  => nointegritychecks is on: bcdedit /set nointegritychecks off ; reboot.' }
  elseif($joined -match 'unacceptable configuration'){ W '  => testsigning satisfied but Javelin dislikes something else; candidate #1 is our own loaded driver: sc stop apexdrv, retest.' }
} elseif($firstPid -eq 0){
  W '  NO GAME SEEN. Start Apex by hand, then re-run without -Launch.'
} elseif($deadAfterUp){
  W ('  game pid {0} started then EXITED with no matching popup text - check the rows above.' -f $firstPid)
} else {
  W ('  GATE CLOSED: game alive (pid {0}), no Javelin popup for {1} s.' -f $firstPid,$elapsed)
  W '  => TESTSIGNING may stay ON and apexdrv may stay RUNNING (B3 kernel inject usable).'
  W '  NEXT: run28.cmd  (stage 2: probe + inject apexcheat.dll + payload-log proof).'
}
W ''
W "-- p27 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
