# p31 - REBOOT CHOREOGRAPHY (run non-admin; nothing here needs elevation).
#   A: snapshot the exact pre-reboot state (boot flags, services, driver files, AC leftovers)
#   B: arm a one-shot logon verification (HKCU RunOnce -> run22.cmd) so the post-reboot check
#      runs itself instead of being forgotten
#   C: reboot with 20s of grace (full restart - hiberboot only affects shutdown, not restart,
#      so the driver/EAAC state really is torn down)
# Result: _ritual\p31_prereboot.txt (this file), _ritual\p22.txt (after logon).
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p31_prereboot.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
function W($t){ $t | Add-Content -LiteralPath $o }
"=== p31 PRE-REBOOT SNAPSHOT $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm ===" | Set-Content -LiteralPath $o

W ''
W '########## A: boot flags that Javelin reads (live BCD) ##########'
$bcd = & bcdedit /enum '{current}' 2>&1
foreach($k in @('identifier','testsigning','nointegritychecks','debug','hypervisorlaunchtype','bootmenupolicy')){
  $hit = @($bcd | Where-Object { $_ -match ("^\s*" + $k) })
  if($hit.Count -eq 0){ W ("  {0,-20} (absent)" -f $k) } else { $hit | ForEach-Object { W ('  ' + $_.ToString().Trim()) } }
}
W '  NOTE: SystemStartOptions in the registry still shows TESTSIGNING because that is the BOOTED'
W '        config; it drops only at the next boot. That is exactly what this reboot is for.'
W ("  backup present: bcd_before_20261101_204255.bcd = {0}" -f (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bcd_before_20261101_204255.bcd')))

W ''
W '########## B: lab services (must all be ABSENT) + AC state ##########'
foreach($s in @('apexdrv','apexdrv_cat','kernprobe')){
  $q = (& sc.exe query $s 2>&1)
  $st = ($q | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() }) -join ' | '
  $miss = ($q -join ' ') -match '1060'
  W ("  {0,-12} present={1}  {2}" -f $s,(-not $miss),$st)
}
foreach($s in @('EAAntiCheatService','EAAntiCheat','EasyAntiCheat','gdrv3','MSIO','voicemodvad','Xvdd','VBoxSup')){
  $sv = Get-Service -Name $s -ErrorAction SilentlyContinue
  W ("  {0,-20} {1}" -f $s, $(if($sv){ $sv.Status } else { '(not installed)' }))
}

W ''
W '########## C: apexdrv binaries on the box ##########'
foreach($d in @("$env:WINDIR\System32\drivers", (Join-Path (Split-Path $PSScriptRoot -Parent) 'QwenKernPremium\build'))){
  $f = @(Get-ChildItem -LiteralPath $d -Filter 'apexdrv*' -ErrorAction SilentlyContinue)
  if($f.Count -eq 0){ W ("  {0}: (none)" -f $d) } else { $f | ForEach-Object { W ("  {0}\{1}  {2} bytes" -f $d,$_.Name,$_.Length) } }
}

W ''
W '########## D: EA / AC processes alive right now ##########'
$ea = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'apex|eac|EA|Origin|javelin|QwenKern|apex_launcher' } | Sort-Object ProcessName)
if($ea.Count -eq 0){ W '  (none)' } else { $ea | ForEach-Object { W ("  {0,-28} pid={1}" -f $_.ProcessName,$_.Id) } }
W '  (any leftovers listed above die with this reboot)'

W ''
W '########## E: arm one-shot logon verification ##########'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$val = 'cmd /c ""' + (Join-Path $PSScriptRoot 'run22.cmd') + '""'
try {
  if(-not (Test-Path $key)){ New-Item -Path $key -Force | Out-Null }
  Set-ItemProperty -Path $key -Name 'QwenKern_BootVerify' -Value $val -Type String
  W ("  RunOnce QwenKern_BootVerify = {0}" -f (Get-ItemProperty -Path $key -Name 'QwenKern_BootVerify').QwenKern_BootVerify)
  W '  -> after logon run22.cmd fires by itself; read _ritual\p22.txt. If p22 pops UAC, approve it.'
  W '  -> to cancel: Remove-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce QwenKern_BootVerify'
} catch { W ("  !! could not arm RunOnce: {0}" -f $_.Exception.Message) }

W ''
W '########## F: reboot now (t-20s, /f) ##########'
W '  next steps after logon: read _ritual\p31_reboot.txt + _ritual\p22.txt, then _ritual\run27.cmd (gate test).'
W '  DO NOT launch Apex by hand before run27 - the first post-reboot launch is the measurement.'
W "-- p31 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"

shutdown.exe /r /t 20 /f /c "Javelin baseline: TESTSIGNING off + apexdrv removed. After logon read _ritual\p22.txt, then run _ritual\run27.cmd"
W ("shutdown rc={0} at {1}" -f $LASTEXITCODE, (Get-Date -f 'HH:mm:ss'))
