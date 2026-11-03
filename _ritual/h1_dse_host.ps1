# h1 - HOST milestone 1a: open DSE with kdu, load apexdrv, restore DSE, LEAVE THE DRIVER RUNNING.
#
# Proven in guest as k9 (RESULT: PASS via prv 22). This is the host rerun of the same chain:
#   baseline 577 -> kdu -prv 22 -dse 0 (verify) -> sc start apexdrv (rc 0, STATE 4 RUNNING)
#   -> kdu -prv 22 -dse <pre-value> (verify + readback) -> driver left RUNNING for the G1 gate run (h2).
#   Restore target is the value kdu printed BEFORE the flip (16 on this box), not the constant 6:
#   restoring 6 leaves ci!g_CiOptions different from the byte PatchGuard hashed at boot -> 0x109
#   CRITICAL_STRUCTURE_CORRUPTION ~20 min later (evidence: _ritual\_crash_finding.txt).
#
# Pre-flight aborts unless: apexdrv staged+stopped at 577 with the k9-proven binary (hash 9B119FD0...),
# blocklist 0, HVCI not running, no game/EAAC process alive. Safe by construction: if anything fails
# after DSE was opened, the finally block still restores the recorded pre-value.
#
# Writes: _ritual\h1_host.txt   (self-elevates; kdu rc=1 on success too - gate on output strings only)
$ErrorActionPreference = 'Continue'
$rit  = $PSScriptRoot
$pay  = 'C:\p37vm\payload'
$o    = Join-Path $rit 'h1_host.txt'
$svc  = 'apexdrv'
$bin  = "$env:WINDIR\System32\drivers\apexdrv.sys"
$sha  = '9B119FD0C38740A2'   # first 16 hex of SHA256, k9-proven build
$adm  = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  $ea = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  Start-Process powershell -Verb RunAs -ArgumentList $ea
  exit
}
$dup = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'h1_dse_host' -and $_.ProcessId -ne $PID })
if($dup.Count){ foreach($d in $dup){ Stop-Process -Id $d.ProcessId -Force -EA SilentlyContinue }; Start-Sleep -Seconds 2 }

function W($t){ $t | Add-Content -LiteralPath $o }
$script:lastOut = ''
function RunExe([string]$exe, [string[]]$argv, [int]$capMs = 14000) {
    $q = ''
    foreach ($a in $argv) { if ($a -match '[\s"]') { $q += ' "' + ($a -replace '"', '\"') + '"' } else { $q += ' ' + $a } }
    W ('$ ' + (Split-Path $exe -Leaf) + $q)
    $rc = -999; $out = ''
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $q.Trim()
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $pay
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $tO = $p.StandardOutput.ReadToEndAsync(); $tE = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($capMs)) { W ('  TIMEOUT ' + $capMs + 'ms'); try { $p.Kill() } catch { }; try { [void]$p.WaitForExit(3000) } catch { } }
        else { try { [void]$p.WaitForExit(2000) } catch { } }
        try { $rc = $p.ExitCode } catch { }
        foreach ($t in $tO, $tE) { if ($t.Wait(2500) -and $t.IsCompleted) { try { $out += $t.Result } catch { } } else { W '  (stream did not close)' } }
    } catch { W ('  LAUNCH FAIL ' + $_.Exception.Message) }
    if ($out) { $out = $out -replace "`r`n", "`n" }
    W ('  exit=' + $rc)
    $i = 0
    foreach ($line in ($out -split "`n")) { if ($i -ge 40) { W '  | ...'; break }; if ($line.Trim() -ne '') { W ('  | ' + $line.TrimEnd()) }; $i++ }
    $script:lastOut = $out
    return $rc
}
function Svc([string]$argline, [int]$capMs = 6000) { return RunExe "$env:SystemRoot\system32\sc.exe" ($argline -split ' ') $capMs }
function DrvRunning { (((& sc.exe query $svc 2>&1) -join ' ') -match 'STATE\s+:\s+4\s+RUNNING') }

$dseOpened = $false
$winner = -1
$loaded = $false
$preDse = -1        # the boot-time value kdu reports = the ONLY correct restore target
try {
    "=== h1 HOST DSE FLIP $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') pid=$PID admin=$adm host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
    W '  pre-flight gates - abort on any FAIL, nothing is mutated before they all pass.'

    # ---- gates -----------------------------------------------------------------
    $fail = 0
    $qv = ((& sc.exe qc $svc 2>&1) -join ' ')
    $svcOk = ($qv -notmatch '1060') -and ($qv -match 'apexdrv\.sys')
    if(-not $svcOk){ $fail++; W '  FAIL: service apexdrv missing or binPath is not apexdrv.sys' } else { W '  pass: service apexdrv staged' }
    $qs = ((& sc.exe query $svc 2>&1) -join ' ')
    if($qs -match 'STOPPED'){ W '  pass: service is STOPPED' } elseif($qs -match 'RUNNING'){ $fail++; W '  FAIL: service already RUNNING (h1 expects a fresh run; stop it first)' } else { $fail++; W ('  ? service state unreadable: ' + $qs) }
    if($qs -match '577'){ W '  pass: last exit 577 = DSE armed, the baseline to reproduce' } else { W ('  ? last exit not 577 - baseline start must show 577; full: ' + $qs) }
    $h = (Get-FileHash -LiteralPath $bin -Algorithm SHA256 -EA SilentlyContinue).Hash
    if($h -like ($sha + '*')){ W ('  pass: binPath hash ' + $h + ' = k9-proven build') } else { $fail++; W ('  FAIL: binPath hash ' + $h + ' does not match ' + $sha) }
    $bl = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -Name VulnerableDriverBlocklistEnable -EA SilentlyContinue).VulnerableDriverBlocklistEnable
    if($bl -eq 0){ W '  pass: VulnerableDriverBlocklistEnable = 0 (live)' } else { $fail++; W ('  FAIL: blocklist = ' + $bl + ' (kdu providers get 0xC0000603) - set it to 0 first') }
    $ssr = @((Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -EA SilentlyContinue).SecurityServicesRunning)
    if($ssr -contains 1){ $fail++; W ('  FAIL: HVCI is running (SecurityServicesRunning=' + ($ssr -join ',') + ')') } else { W ('  pass: HVCI not running (SecurityServicesRunning=' + ($ssr -join ',') + ')') }
    $g = @(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|EAAntiCheat|EADesktop' })
    if($g.Count){ $fail++; W ('  FAIL: game/EA processes alive: ' + (($g | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ',')) } else { W '  pass: no game/EA process alive' }
    foreach($f in 'kdu.exe','drv64.dll'){ if(-not (Test-Path -LiteralPath (Join-Path $pay $f))){ $fail++; W ('  FAIL: missing ' + $f) } }
    if($fail){ W '=== VERDICT ==='; W ('RESULT: ABORT - ' + $fail + ' pre-flight failure(s)'); return }
    W ('  info: gdrv3 = ' + ((Get-Service gdrv3 -EA SilentlyContinue).Status) + ' (stays running; independent of AsIO3)')
    foreach($f in 'kdu.exe','drv64.dll'){ Unblock-File -LiteralPath (Join-Path $pay $f) -EA SilentlyContinue }
    try { Add-MpPreference -ExclusionPath $pay -EA Stop; W '  defender exclusion on payload dir: ok' } catch { W ('  defender exclusion: ' + $_.Exception.Message) }

    # ---- baseline --------------------------------------------------------------
    W ''
    W '## STEP baseline: sc start (expect 577 = DSE armed before we touch anything)'
    $rcBase = Svc ('start ' + $svc) 8000
    if($rcBase -eq 577){ W '  BASELINE OK: 577, DSE armed' }
    elseif($rcBase -eq 0){ W '  WARN: started anyway (0) - DSE was already open; continue, restore will still fire' }
    else { W ('  ABORT: unexpected baseline rc ' + $rcBase); W '=== VERDICT ==='; W 'RESULT: ABORT - baseline not 577/0'; return }
    if(DrvRunning){ Svc ('stop ' + $svc) 6000 | Out-Null }

    # ---- ladder ----------------------------------------------------------------
    W ''
    W '## STEP ladder: kdu -prv <id> -dse 0 (gate on "verification succeeded")'
    foreach($id in @(22, 20, 13, 11, 4, 2, 7, 3, 1, 0)){
        W ('STEP=prv' + $id)
        $null = RunExe (Join-Path $pay 'kdu.exe') @('-prv', "$id", '-dse', '0') 20000
        $od = $script:lastOut
        if($od -match 'revoked' -or $od -match '0xC0000603'){ W ('  prv ' + $id + ' DEAD cert-revoked'); continue }
        if($od -match 'Unable to load'){ W ('  prv ' + $id + ' DEAD load refused'); continue }
        if($od -match 'not available' -or $od -match 'Unknown provider'){ W ('  prv ' + $id + ' unavailable'); continue }
        if($od -match 'verification succeeded'){ W ('  prv ' + $id + ' DSE WRITE VERIFIED'); $winner = $id; $dseOpened = $true; break }
        W ('  prv ' + $id + ' no verdict (rc ignored by design)')
    }
    W ('WINNER=' + $winner)
    if($winner -lt 0){ W '=== VERDICT ==='; W 'RESULT: FAIL - no provider wrote DSE (blocklist / revocation)'; return }

    # ---- capture the boot value that was just overwritten -----------------------
    # PatchGuard hashed this dword at boot. Restoring a constant (6) leaves the byte different ->
    # 0x109 CRITICAL_STRUCTURE_CORRUPTION ~20 min later (param4=0 generic data region, param3=this VA).
    # kdu prints this dword in HEX but parses the -dse argument in DECIMAL. Passing the printed
    # text straight back turns boot 0x16 into 0x10 (observed: h1 boot 4, readback 10 vs expect 16).
    # So: keep the printed form as hex TEXT for comparison, and convert to decimal only for -dse.
    $null = $script:lastOut -match 'value:\s*([0-9A-Fa-f]+)\s*,\s*new value to be written'
    $preDseHex = ''; $preDse = -1
    if($Matches){ $preDseHex = $Matches[1].ToUpper(); $preDse = [Convert]::ToInt32($preDseHex, 16) }
    W ('  PRE-DSE=0x' + $preDseHex + ' (restore target; kdu prints hex, -dse eats decimal -> pass ' + $preDse + ')')

    # ---- load ------------------------------------------------------------------
    W ''
    W '## STEP load: sc start apexdrv inside the open window'
    $rcLoad = Svc ('start ' + $svc) 8000
    Start-Sleep 2
    $loaded = DrvRunning
    W ('  start rc=' + $rcLoad + ' RUNNING=' + $loaded + ' :: ' + (((& sc.exe query $svc 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() }) -join ' '))

    # ---- restore ---------------------------------------------------------------
    W ''
    W ('## STEP restore: kdu -prv <winner> -dse ' + $preDse + ' (boot value, NOT a constant)')
    $null = RunExe (Join-Path $pay 'kdu.exe') @('-prv', "$winner", '-dse', "$preDse") 20000
    $restored = ($script:lastOut -match 'verification succeeded')
    # second pass = read-back; kdu prints the current value before writing, so this both reads and is idempotent
    $null = RunExe (Join-Path $pay 'kdu.exe') @('-prv', "$winner", '-dse', "$preDse") 20000
    $back = ''
    if($script:lastOut -match 'value:\s*([0-9A-Fa-f]+)'){ $back = $Matches[1].ToUpper() }
    $restored = ($restored -and ($back -eq $preDseHex))
    $dseOpened = -not $restored
    W ('  restore verified=' + $restored + ' readback=0x' + $back + ' expect=0x' + $preDseHex + ' (hex compare)')

    W ''
    W '=== VERDICT ==='
    if($loaded -and $restored){ W ('RESULT: PASS via prv ' + $winner + ' - driver RUNNING, DSE restored to boot value 0x' + $preDseHex + ' (readback verified), left RUNNING for h2'); W 'NEXT: run _ritual\h2_gate.ps1 (G1 gate run, 30 min) IN THIS BOOT - crash horizon ~20 min if the value is wrong' }
    elseif($loaded){ W ('RESULT: PARTIAL via prv ' + $winner + ' - driver RUNNING but restore line missing; DSE may still be 0') }
    else { W ('RESULT: FAIL via prv ' + $winner + ' - DSE written, load rc=' + $rcLoad) }
} catch { W ('UNCAUGHT ' + $_.Exception.Message) }
finally {
    if($dseOpened -and $winner -ge 0 -and $preDse -ge 0){
        W ('  finally: DSE open/mismatched - forcing -dse ' + $preDse + ' (decimal for 0x' + $preDseHex + ')')
        $null = RunExe (Join-Path $pay 'kdu.exe') @('-prv', "$winner", '-dse', "$preDse") 20000
        $fb = ''
        if($script:lastOut -match 'value:\s*([0-9A-Fa-f]+)'){ $fb = $Matches[1].ToUpper() }
        W ('  finally restore verified=' + ($script:lastOut -match 'verification succeeded') + ' readback=0x' + $fb + ' expect=0x' + $preDseHex + ' match=' + ($fb -eq $preDseHex))
    } elseif($dseOpened -and $winner -ge 0){
        W '  finally: pre-DSE unparsed - falling back to -dse 6 (0x109 risk stands)'
        $null = RunExe (Join-Path $pay 'kdu.exe') @('-prv', "$winner", '-dse', '6') 20000
        W ('  finally restore verified=' + ($script:lastOut -match 'verification succeeded'))
    }
    W ('-- h1 END ' + (Get-Date -f 'HH:mm:ss') + ' driver RUNNING=' + (DrvRunning) + ' --')
}

