# p23 - POST-REBOOT LIVE A/B: with testsigning/nointegritychecks/debug OFF, relaunch the EAAC
# GameServiceLauncher and watch the Application log for a NEW "Security Violation" popup.
# Run AFTER a reboot (run22 first to prove the flags stuck). Close Apex before running.
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p23.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  exit
}
"=== p23 LIVE POPUP A/B $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
function W($t){ $t | Add-Content -LiteralPath $o }

$sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
W ("  SystemStartOptions = [{0}]" -f $sso)
W ("  booted             = {0}" -f $boot)
if($sso -match 'TESTSIGNING'){ W '  !! still TESTSIGNING -> reboot again (or re-run run21) before trusting this test' }
else { W '  ok: TESTSIGNING gone from the booted kernel command line' }

W ''
W '########## A: popups already in the log (last 6 h) - baseline ##########'
$pre = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-6)} -ErrorAction SilentlyContinue |
          Where-Object { $_.Message -match 'Security Violation' })
if(-not $pre){ W '  (none)' } else { $pre | ForEach-Object { W ("  PRE {0} id={1} :: {2}" -f $_.TimeCreated.ToString('HH:mm:ss'),$_.Id,(($_.Message -replace '\s+',' ').Trim())) } }

W ''
W '########## B: close leftovers, relaunch EAAC GameServiceLauncher ##########'
foreach($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|EAAntiCheat|eaanticheat|Apex' })){
  W ("  stopping {0}({1})" -f $p.ProcessName,$p.Id)
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 5
$t0 = Get-Date
$cands = @(
  'C:\Program Files\EA Games\Apex\EAAntiCheat.GameServiceLauncher.exe',
  'C:\Program Files\EA\AC\EAAntiCheat.GameServiceLauncher.exe',
  'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe'
)
$launched = $null
foreach($c in $cands){
  if(Test-Path -LiteralPath $c){
    try { Start-Process -FilePath $c; $launched = $c; W ("  LAUNCHED {0}" -f $c); break }
    catch { W ("  launch failed {0}: {1}" -f $c,$_.Exception.Message) }
  }
}
if(-not $launched){ W '  !! no EAAC launcher image found' }

W ''
W '########## C: watch 150 s for a NEW popup ##########'
$hit = @()
for($i=1; $i -le 15; $i++){
  Start-Sleep -Seconds 10
  $new = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$t0} -ErrorAction SilentlyContinue |
           Where-Object { $_.Message -match 'Security Violation' })
  $svc = (Get-Service -Name 'EAAntiCheatService' -ErrorAction SilentlyContinue).Status
  W ("  t+{0,3}s popups={1} EAAntiCheatService={2}" -f ($i*10),$new.Count,$svc)
  if($new){ $hit = $new; break }
}

W ''
W '########## RESULT ##########'
if($hit){
  W '  POPUP PRESENT -> NEW variant(s):'
  foreach($e in $hit){ W ("   {0} id={1} :: {2}" -f $e.TimeCreated.ToString('HH:mm:ss'),$e.Id,(($e.Message -replace '\s+',' ').Trim())) }
  W '  => same "Test or debug mode" text  = bcdedit change did not take effect (check run22).'
  W '  => "unacceptable configuration"    = TESTSIGNING fixed, but Javelin now dislikes something else'
  W '                                        (our kernprobe = C:\Windows\System32\drivers\apexdrv.sys is candidate #1).'
}
else {
  W '  NO POPUP in 150 s => TESTSIGNING/nointegritychecks were the Javelin kill-flag. Launcher stage PASSES.'
  W '  next: launch Apex itself and play a match; then update _ritual/_index.txt.'
}
W ''
W '-- processes now:'
W ((Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|EAAntiCheat|eaanticheat' } | ForEach-Object { '  ' + $_.ProcessName + '(' + $_.Id + ')' }) -join "`n")
foreach($s in 'EAAntiCheatService','EAAntiCheat','eaanticheat','kernprobe'){
  W ("  sc query {0}: {1}" -f $s, (((& sc.exe query $s 2>&1) -join ' ~ ') -replace '\s+',' '))
}
W ''
W "-- p23 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
