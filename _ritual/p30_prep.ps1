# p30 - ELEVATED PREP for the clean-baseline boot.
# Reason: with TESTSIGNING ON the game is refused either way (driver loaded -> "Device Driver
# signing integrity checks"; driver stopped -> "This software cannot be used at the same time
# as the game").  p21 already removed the boot flag.  This script removes the SECOND variable:
# our own lab driver from the system (3 demand services + 2 copies of apexdrv.sys), so the next
# launch is a vanilla Javelin baseline.  The launcher re-creates the service on demand, and the
# .sys copies are renamed (not deleted) so nothing is lost.
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p30.txt'
function W($t){ $t | Add-Content -LiteralPath $o }

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  "p30 launcher (unelevated) $(Get-Date -f 'HH:mm:ss') - UAC raised; approve it, then read p30.txt." |
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'run30.log')
  exit
}
"=== p30 CLEAN-BASELINE PREP $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
W 'GOAL: before the reboot, remove OUR driver from the system so the next Javelin launch is vanilla:'
W '      3 demand services (apexdrv / apexdrv_cat / kernprobe) + 2 copies of apexdrv.sys.'
W '      Nothing is deleted outright: services are re-creatable by the launcher, .sys files are renamed.'

W ''
W '########## A state BEFORE ##########'
W ("  boot flags: SystemStartOptions = [{0}]" -f ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions))
foreach($s in 'apexdrv','apexdrv_cat','kernprobe'){
  W ("  sc query {0}: {1}" -f $s, ((((& sc.exe query $s 2>&1) -join ' ~ ') -replace '\s+',' ')))
}
$sysdir = 'C:\Windows\System32\drivers'
$copies = @(Get-ChildItem -LiteralPath $sysdir -Force -EA SilentlyContinue | Where-Object { $_.Name -match '^apexdrv.*\.sys' })
$copies += @(Get-ChildItem -LiteralPath 'C:\p26cat' -Force -EA SilentlyContinue | Where-Object { $_.Name -match 'apexdrv.*\.sys$' })
$copies += @(Get-ChildItem -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'QwenKernPremium\build') -Force -EA SilentlyContinue | Where-Object { $_.Name -match 'apexdrv.*\.sys$' })
foreach($c in $copies){ W ("  on disk: {0}  {1} bytes  sig={2}" -f $c.FullName, $c.Length, [string](Get-AuthenticodeSignature -LiteralPath $c.FullName).Status) }
if(-not $copies){ W '  (no apexdrv*.sys found)' }

W ''
W '########## B remove the services ##########'
foreach($s in 'apexdrv','apexdrv_cat','kernprobe'){
  W ("  sc stop {0}: {1}" -f $s, ((((& sc.exe stop $s 2>&1) -join ' ~ ') -replace '\s+',' ')))
}
Start-Sleep -Seconds 2
foreach($s in 'apexdrv','apexdrv_cat','kernprobe'){
  W ("  sc delete {0}: {1}" -f $s, ((((& sc.exe delete $s 2>&1) -join ' ~ ') -replace '\s+',' ')))
}

W ''
W '########## C move the .sys copies out of the driver path ##########'
foreach($c in $copies){
  if($c.DirectoryName -ne $sysdir){ W ("  (left in place, not a driver-path image): {0}" -f $c.FullName); continue }
  $tgt = "$($c.FullName).off"
  if(Test-Path -LiteralPath $tgt){ Remove-Item -LiteralPath $tgt -Force -EA SilentlyContinue }
  try { Move-Item -LiteralPath $c.FullName -Destination $tgt -Force -EA Stop; W ("  renamed: {0} -> {1}" -f $c.FullName, $tgt) }
  catch { W ("  RENAME FAILED {0}: {1}" -f $c.FullName, $_.Exception.Message) }
}

W ''
W '########## D state AFTER ##########'
foreach($s in 'apexdrv','apexdrv_cat','kernprobe'){
  W ("  sc query {0}: {1}" -f $s, ((((& sc.exe query $s 2>&1) -join ' ~ ') -replace '\s+',' ')))
}
W ("  .sys left in drivers dir: {0}" -f (((@(Get-ChildItem -LiteralPath $sysdir -Force -EA SilentlyContinue | Where-Object { $_.Name -match '^apexdrv' }) | ForEach-Object { $_.Name }) -join ' , ') -replace '^$','(none)'))
W ("  leftover popup windows: {0}" -f (((Get-Process -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Security Violation' } | ForEach-Object { $_.ProcessName + ':' + $_.MainWindowTitle }) -join ' | ') -replace '^$','(none)'))
W ("  running EA/AC processes: {0}" -f (((Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'apex|EAAnti|EACef' } | ForEach-Object { $_.ProcessName }) -join ' , ') -replace '^$','(none)'))

W ''
W '########## NEXT ##########'
W '  1. REBOOT now (this is what clears the dirty EAAC state + drops TESTSIGNING from the boot config).'
W '  2. after the reboot run:  run22.cmd   (post-reboot verification: flags + services + who is on the box)'
W '  3. then run:              run27.cmd   (gate test: launch Apex vanilla, 150 s watch)'
W '  4. if the game SURVIVES -> run28.cmd  (inject; INSERT toggles the menu; expect %LOCALAPPDATA%\QwenKern\payload_<pid>.log)'
W ("-- p30 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --")
