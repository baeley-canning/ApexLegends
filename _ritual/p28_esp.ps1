# p28 - ESP-IN-GAME, STAGE 2: probe -> inject apexcheat.dll -> payload-log PROOF.
# Self-elevating (the launcher needs an elevated token for PROCESS_ALL_ACCESS on the game).
# Precondition: r5apex_dx12.exe is running and past the lobby (stage 1 = p27_gate.ps1 green).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p28_esp.ps1 [-GamePid 1234] [-Method nt]
# Writes: _ritual\p28_esp.txt, _ritual\p28_launcher_*.txt, _ritual\p28_payload_<pid>.log
# p31d FIX: the param used to be named $Pid, and PowerShell 5.1 refuses it ("Cannot overwrite
# variable Pid because it is read-only or constant") -> the script died at PARAMETER BINDING,
# before a single line of the body ran: no output file, no error, no UAC, nothing.  Now $GamePid.
param([int]$GamePid = 0, [string]$Method = 'nt', [int]$ObserveSec = 45)
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p28_esp.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-GamePid',"$GamePid",'-Method',$Method)
  exit
}
"=== p28 ESP STAGE 2 $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm requestedMethod=$Method pid=$GamePid ===" | Set-Content -LiteralPath $o

$BUILD    = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
$LAUNCHER = Join-Path $BUILD 'apex_launcher.exe'
$DLL      = Join-Path $BUILD 'apexcheat.dll'
$DRV      = Join-Path $BUILD 'apexdrv.sys'
$GAMEDIR  = 'C:\Program Files\EA Games\Apex'
# p31b FIX: ProcessName has NO ".exe" (PowerShell strips it), so a
# "$GAME -contains $_.ProcessName" test against '*.exe' entries never matched -> p28
# aborted with "game not running" on a live game.  Extensionless, dx12 preferred below.
$GAME     = @('r5apex_dx12','r5apex','baeleys')

W ''
W '########## A: pre-flight ##########'
foreach($f in @($LAUNCHER,$DLL,$DRV)){ W ("  {0} exists={1} {2} bytes" -f $f,(Test-Path -LiteralPath $f), (Get-Item -LiteralPath $f -ErrorAction SilentlyContinue).Length) }
$p = $null
if($GamePid -ne 0){ $p = Get-Process -Id $GamePid -ErrorAction SilentlyContinue }
if(-not $p){ $p = Get-Process -ErrorAction SilentlyContinue | Where-Object { $GAME -contains $_.ProcessName } |
              Sort-Object { $_.ProcessName -ne 'r5apex_dx12' } | Select-Object -First 1 }
if(-not $p){ W '  !! game not running: start Apex (stage 1), then re-run. STAGE 2 ABORTED'; W '-- p28 END --'; exit 2 }
$GamePid = $p.Id
W ("  target: {0} pid={1} ws={2} MB" -f $p.ProcessName,$GamePid,[int]($p.WorkingSet64/1MB))
W ("  EAAntiCheatService={0}  apexdrv={1}" -f (Get-Service EAAntiCheatService -ErrorAction SilentlyContinue).Status, (((& sc.exe query apexdrv 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() }) -join ''))

# Config: the payload reads "apexcheat.ini" relative to its CWD (= the game dir when injected
# by the game's loader, but the operator's CWD in a test target).  Write BOTH so the ESP starts
# ON without needing the INSERT toggle.  esp=true => UpdateESP runs from frame 1.
$ini = "# QwenKern apexcheat.ini - written by p28`r`naimbot=false`resp=true`r`nglow=false`r`nrecoil=false`r`n"
foreach($d in @($BUILD,$GAMEDIR)){
  try { Set-Content -LiteralPath (Join-Path $d 'apexcheat.ini') -Value $ini -Encoding ASCII; W ("  wrote {0}" -f (Join-Path $d 'apexcheat.ini')) }
  catch { W ("  !! could not write apexcheat.ini to {0}: {1}" -f $d,$_.Exception.Message) }
}

$log = Join-Path $env:LOCALAPPDATA ("QwenKern\payload_{0}.log" -f $GamePid)
if(Test-Path -LiteralPath $log){ W ("  payload log already exists ({0} bytes) - will diff" -f (Get-Item -LiteralPath $log).Length) }
$logSizeBefore = 0
if(Test-Path -LiteralPath $log){ $logSizeBefore = (Get-Item -LiteralPath $log).Length }
W ("  payload log: {0}" -f $log)

function Log-Tail([int]$n){
  if(-not (Test-Path -LiteralPath $log)){ return @('(no payload log yet)') }
  return @(Get-Content -LiteralPath $log -Tail $n -ErrorAction SilentlyContinue)
}
function HaveProof(){
  if(-not (Test-Path -LiteralPath $log)){ return $false }
  $txt = (Get-Content -LiteralPath $log -ErrorAction SilentlyContinue) -join "`n"
  return ($txt -match 'Application initialized successfully' -or $txt -match 'main loop started')
}

W ''
W '########## B: probe (measure, never injects) ##########'
$probeOut = Join-Path $PSScriptRoot 'p28_launcher_probe.txt'
& $LAUNCHER --probe --pid $GamePid *> $probeOut
W ("  probe exit={0} -> {1}" -f $LASTEXITCODE,$probeOut)
Get-Content -LiteralPath $probeOut -ErrorAction SilentlyContinue | Select-Object -Last 40 | ForEach-Object { W ('   | ' + $_) }

W ''
W '########## C: inject (first rung that leaves PROOF in the payload log) ##########'
$order = @($Method,'nt','apc','crt','hijack','manual') | Select-Object -Unique
$chosen = ''; $attempts = @()
foreach($m in $order){
  if(HaveProof){ break }
  $out = Join-Path $PSScriptRoot ("p28_launcher_{0}.txt" -f $m)
  W ("  --- attempt method={0} ---" -f $m)
  $t = Get-Date
  & $LAUNCHER --pid $GamePid --no-wait --method=$m --inject *> $out
  $rc = $LASTEXITCODE
  Start-Sleep -Seconds 8
  $proof = HaveProof
  $attempts += [pscustomobject]@{ method=$m; exit=$rc; proof=$proof }
  W ("    exit={0} proof={1} elapsed={2:N1}s -> {3}" -f $rc,$proof,((New-TimeSpan -Start $t).TotalSeconds),$out)
  Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Select-Object -Last 18 | ForEach-Object { W ('    | ' + $_) }
  if($proof){ $chosen = $m; break }
}

W ''
W '########## D: payload log (the proof that matters) ##########'
if(-not (Test-Path -LiteralPath $log)){
  W '  !! no payload log was created: the DLL never reached DllMain in the target.'
  W '     suspects: method refused (see exit codes above), or the loader could not map the payload.'
} else {
  $nowSize = (Get-Item -LiteralPath $log).Length
  W ("  log {0} bytes (was {1} before) - copying to _ritual" -f $nowSize,$logSizeBefore)
  Copy-Item -LiteralPath $log -Destination (Join-Path $PSScriptRoot ("p28_payload_{0}.log" -f $GamePid)) -Force
  Log-Tail 60 | ForEach-Object { W ('   | ' + $_) }
}

W ''
W ('########## E: observe {0}s (game survival after injection) ##########' -f $ObserveSec)
$alive = $true
for($i=0; $i -lt $ObserveSec; $i += 5){
  Start-Sleep -Seconds 5
  $q = Get-Process -Id $GamePid -ErrorAction SilentlyContinue
  if(-not $q){ $alive = $false; W ("  t+{0}s GAME DIED" -f ($i+5)); break }
  if(($i % 15) -eq 0){
    $sz = 0; if(Test-Path -LiteralPath $log){ $sz = (Get-Item -LiteralPath $log).Length }
    W ("  t+{0}s alive yes  payloadLog={1} bytes" -f ($i+5),$sz)
  }
}
$finalSize = 0; if(Test-Path -LiteralPath $log){ $finalSize = (Get-Item -LiteralPath $log).Length }

W ''
W '########## F: what the log says about the game ##########'
$txt = ''
if(Test-Path -LiteralPath $log){ $txt = (Get-Content -LiteralPath $log -ErrorAction SilentlyContinue) -join "`n" }
foreach($pat in @('module base','offset validation','features:','InstallHooks','Failed to install','render hooks','D3D12','ESP ')){
  $hit = @(($txt -split "`r?`n") | Where-Object { $_ -match $pat })
  W ("  [{0,-18}] {1} line(s)" -f $pat,$hit.Count)
  $hit | Select-Object -First 6 | ForEach-Object { W ('     ' + $_) }
}
$valid = 0; $total = 0
$m = [regex]::Match($txt,'offset validation:\s*(\d+)\s*/\s*(\d+)')
if($m.Success){ $valid = [int]$m.Groups[1].Value; $total = [int]$m.Groups[2].Value }
$baseFound = ($txt -match 'game module base = 0x[1-9A-F]')

W ''
W '########## VERDICT ##########'
$used = '(none produced proof)'; if($chosen){ $used = $chosen }
W ("  method used       : {0}" -f $used)
W ("  payload proof     : {0}" -f (HaveProof))
if($baseFound){ W '  game module base  : FOUND (payload sees r5apex)' } else { W '  game module base  : not found' }
W ("  offset validation : {0}/{1} probes matched" -f $valid,$total)
W ("  game alive after  : {0}" -f $alive)
W ("  payload log bytes : {0}" -f $finalSize)
W ''
if((HaveProof) -and $baseFound -and $alive){
  W '  STAGE 2 GREEN: payload live in r5apex_dx12.exe, hooks installed, module base resolved.'
  W '  DO THIS NOW (in the game): press INSERT to toggle the ESP, then go into a match / firing range.'
  W '  - boxes appear             -> stage complete; only size/accuracy polish left.'
  W '  - nothing appears, no log  -> STAGE 3: offsets are wrong. Expected: ApexOffsets::VIEW_MATRIX'
  W '    is the RVA of VTP_GetEngineTraceClient (code), not a matrix.  Candidate values to validate:'
  W '    VIEW_MATRIX 0x1B4DFA0 (dumper value) vs 0x022EE01 (code RVA); LOCAL_PLAYER 0x23F6A78 vs'
  W '    0x01E7D4B8; ENTITY_LIST 0x23F6A90 vs 0x0335D680 / 0x03013C80 / 0x02FCA848; entity origin'
  W '    0x258 vs 0x330, health 0x3A0 vs 0x5E0, team 0x478 vs 0x10E8.  Hunt tool:'
  W '    _ritual\p26_player_probe.ps1 (external scan) - but the 18:17 measurement had external'
  W '    NtReadVirtualMemory on r5apex return 0xC000000D, so the in-payload scan is the reliable one.'
} elseif(HaveProof){
  W '  payload proof present but module base / offset validation not fully green - read D and F.'
} else {
  W '  NO PROOF. Work down the attempt rows in C: the exit code names the rung verdict.'
  W '  If every usermode rung fails, the next lever is the kernel rung B3 (needs apexdrv RUNNING,'
  W '  which is true today only while TESTSIGNING stays on).'
}
W ''
W "-- p28 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
