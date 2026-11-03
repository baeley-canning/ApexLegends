# p35 - SERVICE/DEREGISTRATION DISCRIMINATOR (completes p34).
#
# p34 result pattern (TA driver STOPPED, TB driver RUNNING, both with the flag strings clean on a
# test-mode boot): the game never even spawns - only EAAntiCheat.GameServiceLauncher runs for ~4 s,
# leaves an "EA Javelin Anticheat" id=1000 ExitType event, and exits. p27 proved a vanilla boot with
# apexdrv fully de-registered DOES run the game (window 'Apex Legends' for 300 s, pid present).
# So the remaining variable is not "driver loaded" but "our driver/service exists at all".
#
# This probe varies exactly that, in one boot, with everything else frozen:
#   T1 as-is        : service registered, driver STOPPED
#   T2 de-registered: sc delete apexdrv + rename System32\drivers\apexdrv.sys -> .off
#   T3 re-staged    : copy build\apexdrv.sys back, sc create + sc start (driver RUNNING)
#
#   T2 runs, T1/T3 refuse -> the trigger is OUR registration/shape, test mode itself is fine.
#   T1/T2/T3 all refuse   -> the test-mode boot is fatal by itself (RED -> real signing / manual map).
#   T3 runs               -> ship the test-mode boot with the driver loaded.
#
# Writes: _ritual\p35_matrix.txt
$ErrorActionPreference = 'Continue'
$rit  = $PSScriptRoot
$adm  = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$bcd  = 'C:\Windows\System32\bcdedit.exe'
$reg  = 'HKLM:\SYSTEM\CurrentControlSet\Control'
$exe  = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$drv  = 'C:\Windows\System32\drivers\apexdrv.sys'
$bsrc = Join-Path (Split-Path $rit -Parent) 'QwenKernPremium\build\apexdrv.sys'
$o    = Join-Path $rit 'p35_matrix.txt'

if(-not $adm){
  Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  exit
}
$dup = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'p35_matrix' -and $_.ProcessId -ne $PID })
foreach($d in $dup){ Stop-Process -Id $d.ProcessId -Force -EA SilentlyContinue }
if($dup.Count){ Start-Sleep -Seconds 2 }

function W($t){ $t | Add-Content -LiteralPath $o }
function DrvState { (((& sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING') }
function DrvExists { [bool]((( & sc.exe query apexdrv 2>&1) -join ' ') -match 'SERVICE_NAME') }
function SvcState($n){ $s = ((& sc.exe query $n 2>&1) -join ' '); if($s -match 'STATE\s+:\s+\d+\s+(\w+)'){ $Matches[1] } else { 'ABSENT' } }
function Msg240($m){ $c = ($m -replace '\s+',' ').Trim(); $c.Substring(0,[Math]::Min(240,$c.Length)) }
function IsGame($p){
  if($p.ProcessName -match 'r5apex|baeley'){ return $true }
  $pt = ''
  try { $pt = $p.Path } catch {}
  return [bool]($pt -like 'C:\Program Files\EA Games\Apex\*')
}
function Get-Game {
  $all = @(Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ })
  if(-not $all.Count){ return $null }
  $g = @($all | Where-Object { $_.ProcessName -match 'r5apex|baeley' })
  if($g.Count){ return $g[0] }
  return $all[0]
}
function GameSet { (@(Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ }) | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ',' }
function TitleSet { (@(Get-Process -EA SilentlyContinue | Where-Object { $_.MainWindowTitle }) | ForEach-Object { $_.ProcessName + ':' + $_.MainWindowTitle }) -join ' | ' }
$RX = 'Security Violation|signing integrity checks must be enabled|must be disabled to start|unacceptable configuration|same time as the game'

function SnapState($tag){
  W ("  [$tag] $(Get-Date -f 'HH:mm:ss')  testsigning/nic=" + (((& $bcd /enum '{current}' 2>&1) | Select-String 'testsigning|nointegritychecks') -join ' / '))
  W ("  [$tag] SystemStartOptions = [" + (Get-ItemProperty $reg -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions + ']')
  W ("  [$tag] apexdrv service exists=" + (DrvExists) + ' RUNNING=' + (DrvState) + '  file=' + (Test-Path $drv) + '  eaanticheat=' + (SvcState 'eaanticheat') + '  svc=' + (SvcState 'EAAntiCheatService'))
  W ("  [$tag] leftovers: game=" + ((Get-Game | Measure-Object).Count) + '  EADesktop=' + ((Get-Process EADesktop -EA SilentlyContinue | Measure-Object).Count))
}
function Clear-Game {
  Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ } | ForEach-Object { try { $_.Kill() } catch {} }
  for($i=0; $i -lt 30; $i++){ if(-not (Get-Game)){ break }; Start-Sleep -Seconds 1 }
}

function Watch-Game($tag,$sec){
  Clear-Game
  $t0 = Get-Date
  $seen = @{}
  $pobj = $null
  $popups = 0
  Start-Process -FilePath $exe | Out-Null
  W "  [$tag] launched r5apex_dx12 at $($t0.ToString('HH:mm:ss'))  (sampling 1 s, window ${sec}s)"
  $firstSeen = 0; $lastSeen = 0; $died = $false; $up = 0; $pname = ''; $sawApexWindow = $false
  for($el=1; $el -le $sec; $el++){
    Start-Sleep -Seconds 1
    $p = Get-Game
    $titles = TitleSet
    if($titles -match 'Apex Legends'){
      if(-not $sawApexWindow){ $sawApexWindow = $true; W ("  [{0}] t+{1}s APEX WINDOW UP : {2}" -f $tag,$el,$titles) }
      $lastSeen = $el
      if(-not $firstSeen){ $firstSeen = $el }
    }
    if($p){
      if(-not $firstSeen){ $firstSeen = $el; $pobj = $p; $pname = $p.ProcessName; W ("  [{0}] t+{1}s PROCESS UP pid={2} name={3}" -f $tag,$el,$p.Id,$p.ProcessName) }
      if(-not $sawApexWindow -and $p.MainWindowTitle){ W ("  [{0}] t+{1}s title = {2}" -f $tag,$el,$p.MainWindowTitle) }
      $lastSeen = $el
    } elseif($firstSeen -and -not $died -and -not $sawApexWindow){
      $died = $true; $up = $lastSeen - $firstSeen
      $code = 'n/a'
      if($pobj){ try { $pobj.Refresh(); if($pobj.HasExited){ $code = '0x{0:X8}' -f $pobj.ExitCode } } catch { $code = 'handle-lost' } }
      W ("  [{0}] t+{1}s ALL GAME PROCESSES GONE after ~{2}s  exit={3}" -f $tag,$el,$up,$code)
    }
    if(($el % 10) -eq 0){
      W ("  [{0}] t+{1}s  apexdrv={2} set=[{3}] titles=[{4}]" -f $tag,$el,(DrvState),(GameSet),$titles)
    }
    foreach($lg in 'Application','System'){
      foreach($e in @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=(Get-Date).AddSeconds(-2)} -EA SilentlyContinue)){
        $key = "$lg|$($e.RecordId)"
        if($seen[$key]){ continue }
        $seen[$key] = 1
        $isPop = [bool]($e.Message -match $RX)
        if($isPop){ $popups++ }
        if($isPop -or ($e.ProviderName -match 'EA Javelin|FilterManager|Application Popup|Application Error|Windows Error')){
          $kind = ' EVT '
          if($isPop){ $kind = ' POPUP ' }
          W ('    ' + $tag + $kind + $e.TimeCreated.ToString('HH:mm:ss') + ' ' + $lg + ' id=' + $e.Id + ' src=' + $e.ProviderName + ' :: ' + (Msg240 $e.Message))
        }
      }
    }
    if($died -and $el -ge ($lastSeen + 20)){ W "  [$tag] (stopping 20 s after everything died)"; break }
  }
  $alive = [bool](Get-Game) -or [bool](TitleSet -match 'Apex Legends')
  W ("  [{0}] RESULT alive={1} died={2} uptime={3}s popups={4} apexWindow={5} name='{6}'  apexdrv_RUNNING={7}" -f $tag,$alive,$died,$up,$popups,$sawApexWindow,$pname,(DrvState))
  return [pscustomobject]@{ alive=$alive; died=$died; uptime=$up; popups=$popups; window=$sawApexWindow }
}

