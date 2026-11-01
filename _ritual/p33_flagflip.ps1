# p33 - THE FLAG-FLIP EXPERIMENT (decides whether the driver and a live game can coexist).
#
#   testsigning ON  -> DSE bypassed -> self-signed apexdrv.sys CAN load ... but Javelin refuses
#                      (Security Violation popup, game dies; fatal even if OK is clicked - p9 14:39)
#   testsigning OFF -> game runs clean (run27 20:52: 300 s, no popup, ws 6.8 GB) ... but apexdrv is
#                      577 (DSE wants an MS-root chain; every self-signed shape in p24-p26 failed /kp)
#
# UNDER TEST: BOOT with testsigning ON so the driver loads, then flip the FLAG off LIVE - BCD first,
# then the registry SystemStartOptions - relaunching the game after each flip. The driver stays
# loaded (no reboot), so if Javelin reads a flag rather than the live kernel CI state, one of the
# flip states runs the game WITH the driver up => B3 (kernel inject) usable with testsigning off.
#
# Phase A (no -PostBoot): stage driver, testsigning ON, arm RunOnce -> run33.cmd, reboot.
# Phase B (-PostBoot, self-elevating): T1 baseline / T2 BCD-off / T3 BCD-off + registry scrub.
# Writes: _ritual\p33_prereboot.txt, _ritual\p33_flagflip.txt
param([switch]$PostBoot)
$ErrorActionPreference = 'Continue'
$rit  = $PSScriptRoot
$adm  = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$bcd  = 'C:\Windows\System32\bcdedit.exe'
$reg  = 'HKLM:\SYSTEM\CurrentControlSet\Control'
$drv  = 'C:\Windows\System32\drivers\apexdrv.sys'
$bsrc = Join-Path (Split-Path $rit -Parent) 'QwenKernPremium\build\apexdrv.sys'
$exe  = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$ead  = 'C:\Program Files\Electronic Arts\EA Desktop\13.813.1.6327-1792985412\EA Desktop\EADesktop.exe'
$RX   = 'Security Violation|must be disabled to start|signing integrity checks must be enabled|unacceptable configuration'

if(-not $adm){
  $ea = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  if($PostBoot){ $ea += '-PostBoot' }
  Start-Process powershell -Verb RunAs -ArgumentList $ea
  exit
}

# ==================================================================== PHASE A
if(-not $PostBoot){
  $o = Join-Path $rit 'p33_prereboot.txt'
  function W($t){ $t | Add-Content -LiteralPath $o }
  "=== p33 PHASE A $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm ===" | Set-Content -LiteralPath $o
  W ('  SystemStartOptions = [' + (Get-ItemProperty $reg -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions + ']')
  W ('  bcd now            : ' + (((& $bcd /enum 2>&1) | Select-String 'testsigning|nointegritychecks|debug') -join ' / '))
  W ('  driver staged already? ' + (Test-Path $drv))
  Copy-Item -LiteralPath $bsrc -Destination $drv -Force
  W ('  staged -> ' + $drv + '  ' + (Get-Item $drv).Length + ' bytes  sig=' + (Get-AuthenticodeSignature $drv).Status)
  W ('  testsigning ON  : ' + (((& $bcd /set '{current}' testsigning on 2>&1)) -join ' '))
  W ('  nointegrity OFF : ' + (((& $bcd /set '{current}' nointegritychecks off 2>&1)) -join ' '))
  W ('  after           : ' + (((& $bcd /enum 2>&1) | Select-String 'testsigning|nointegritychecks') -join ' / '))
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'QwenKern_FlagFlip' -Value ('cmd /c "' + (Join-Path $rit 'run33.cmd') + '"')
  W '  RunOnce armed: QwenKern_FlagFlip -> run33.cmd (phase B self-elevates after logon)'
  W '  >>> rebooting in 25 s'
  Get-Content -LiteralPath $o
  & shutdown /r /t 25 /f
  exit
}

# ==================================================================== PHASE B
$o = Join-Path $rit 'p33_flagflip.txt'
function W($t){ ("{0}  {1}" -f (Get-Date -f 'HH:mm:ss'),$t) | Add-Content -LiteralPath $o }
"=== p33 PHASE B $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm ===" | Set-Content -LiteralPath $o
$sso = (Get-ItemProperty $reg -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions
W ("  SystemStartOptions = [$sso]")
W ("  kernel booted in TEST MODE = " + [bool]($sso -match 'TESTSIGNING'))
W ("  LastBoot = " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
W ('  bcd      : ' + (((& $bcd /enum 2>&1) | Select-String 'testsigning|nointegritychecks') -join ' / '))
W ''
W '########## 1: load apexdrv (this boot has testsigning ON for exactly this reason) ##########'
& sc.exe delete apexdrv *> $null
Start-Sleep -Milliseconds 600
W ('  create: ' + (((& sc.exe create apexdrv type= kernel start= demand binPath= ('"'+$drv+'"') DisplayName= 'QwenKern apexdrv' 2>&1) -join ' ')))
W ('  start : ' + (((& sc.exe start apexdrv 2>&1) -join ' ')))
Start-Sleep -Seconds 2
W ('  query : ' + ((((& sc.exe query apexdrv 2>&1) -join ' ') -replace '\s+',' ')))
Add-Type -Namespace P33 -Name K -MemberDefinition @'
[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateFileW(string n, uint a, uint sh, IntPtr sec, uint disp, uint fl, IntPtr t);
'@
$h = [P33.K]::CreateFileW('\\.\ApexDrv', 0xC0000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
W ('  \\\\.\\ApexDrv handle=' + $h + ' lastErr=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
$drvUp0 = (((& sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING')
W ('  driver RUNNING before any flip = ' + $drvUp0)
if(-not $drvUp0){ W '  !! driver failed to load even in test mode - experiment void (report anyway)' }

# ==================================================================== PHASE B, part 2: the trials
function Watch-Game([string]$tag,[int]$sec){
  Get-Process r5apex_dx12 -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
  Start-Sleep -Seconds 3
  if(-not (Get-Process EADesktop -EA SilentlyContinue)){
    if(Test-Path -LiteralPath $ead){ Start-Process -FilePath $ead; W "  [$tag] EA app started"; Start-Sleep -Seconds 6 }
  }
  $t0 = Get-Date
  Start-Process -FilePath $exe | Out-Null
  W "  [$tag] launched r5apex_dx12.exe at $($t0.ToString('HH:mm:ss'))"
  $el = 0; $first = 0; $popup = $false; $died = $false
  while($el -lt $sec){
    Start-Sleep -Seconds 5; $el += 5
    $p = Get-Process r5apex_dx12 -EA SilentlyContinue
    if($p -and $first -eq 0){ $first = $p.Id; W ("  [{0}] t+{1}s GAME UP pid={2}" -f $tag,$el,$p.Id) }
    if($first -ne 0 -and -not $p -and -not $died){ $died = $true; W ("  [{0}] t+{1}s GAME DIED" -f $tag,$el) }
    if(-not $popup){
      foreach($lg in 'Application','System'){
        $ev = @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=$t0} -EA SilentlyContinue | Where-Object { $_.Message -match $RX })
        foreach($e in $ev){ W ('    ' + $tag + ' POPUP ' + $e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' src=' + $e.ProviderName + ' :: ' + (($e.Message -replace '\s+',' ').Trim())) }
        if($ev.Count){ $popup = $true }
      }
    }
    if($popup -and ($died -or $el -ge 45)){ break }
  }
  $alive = [bool](Get-Process r5apex_dx12 -EA SilentlyContinue)
  $drvUp = (((& sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING')
  W ("  [{0}] RESULT popup={1} died={2} alive={3} apexdrv_RUNNING={4}" -f $tag,$popup,$died,$alive,$drvUp)
  return @($popup,$died)
}

W ''
W '########## 2: T1 - as booted (flag ON everywhere) : expect the Javelin refusal ##########'
$r1 = Watch-Game 'T1' 75
W ''
W '########## 3: T2 - BCD flag OFF, live, no reboot (registry untouched) ##########'
W ('  bcdedit: ' + (((& $bcd /set '{current}' testsigning off 2>&1)) -join ' '))
$r2 = Watch-Game 'T2' 75
W ''
W '########## 4: T3 - BCD flag OFF + registry SystemStartOptions scrubbed ##########'
if(-not (Test-Path -LiteralPath (Join-Path $rit '_p33_sso.bak'))){ Set-Content -LiteralPath (Join-Path $rit '_p33_sso.bak') -Value $sso }
$clean = (($sso -replace '\s*TESTSIGNING\s*',' ') -replace '\s+',' ').Trim()
Set-ItemProperty -Path $reg -Name SystemStartOptions -Value $clean
W ('  SystemStartOptions now = [' + $clean + ']   (backup: _p33_sso.bak)')
$r3 = Watch-Game 'T3' 75
W ''
W '########## VERDICT ##########'
W ("  T1 as-booted        : popup={0} died={1}" -f $r1[0],$r1[1])
W ("  T2 bcd-off-live     : popup={0} died={1}" -f $r2[0],$r2[1])
W ("  T3 bcd+reg-scrubbed : popup={0} died={1}" -f $r3[0],$r3[1])
$drvEnd = (((& sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING')
W ("  apexdrv still RUNNING after all trials = " + $drvEnd)
if((-not $r3[0]) -and (-not $r3[1])){
  W '  *** GREEN (T3): Javelin reads the FLAG SOURCE, not the live kernel CI state. ***'
  W '  SHIP IT: boot with testsigning ON (driver loads at boot), scrub SystemStartOptions at logon,'
  W '           driver stays RUNNING while the game runs => B3 kernel inject is available with the game live.'
  W '  NEXT: build/verify the driver-side contract, then run28 / launcher --method=kernel against the live game.'
} elseif((-not $r2[0]) -and (-not $r2[1])){
  W '  *** GREEN (T2): the BCD flag alone is what Javelin reads. ***'
  W '  Needs a logon-time bcdedit flip + a way to keep future boots in test mode (scheduled task pair).'
} else {
  W '  RED: Javelin sees the LIVE kernel CI state (test mode itself), not just a flag.'
  W '  Then apexdrv must pass DSE for real: MS-root chain (cross-sign / WHQL / attestation signing)'
  W '  or manual-map it with a BYOVD primitive (gdrv3 read-only today; MsIo64/MS-signed but map unproven).'
}
W ''
W ("-- p33 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --")
if((-not $r3[0]) -and (-not $r3[1])){ W '  (game left RUNNING on purpose so an injector can attach)' }

