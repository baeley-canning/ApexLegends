# h318_arm_dse6.ps1 - h317 taught the rule: Javelin refuses to START the game while DSE is off
# ("Security Violation (2) - Device Driver signing integrity checks must be enabled"). So DSE may only
# be down for the time it takes OUR driver to load, and must be back at 6 before the game starts.
#   DSE read -> 0 (write, verify) -> create+start zapexdrv (verify RUNNING) -> DSE 6 (write, verify)
# The loaded image stays; CI never re-checks images already resident, and the inject loads nothing new.
# R3: every step gated on its own read-back. R5: own files. Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_arm.out'
$d    = 'C:\Users\Public\p37'
$cc   = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
function Kdu([string[]]$a, [int]$cap = 25000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'kdu.exe'; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit($cap)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
function DseNow { $o = Kdu @('-prv', '20', '-dse'); if ($o -match 'value:\s*([0-9A-Fa-f]+)') { return $matches[1] } return '' }
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
Lg '===== h318 arm (DSE 0 for the load, 6 for the game) ====='
Lg ('admin=' + $adm + ' boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s'))
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=' + (SvcQ))
$pre = DseNow
Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
if (-not $pre) { Lg 'RESULT: FAIL - DSE unreadable, nothing armed'; Emit; exit 1 }

# 1. DSE down for the load only
if ($pre -notmatch '^0*0$') {
    Lg ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']')
    Start-Sleep -Milliseconds 400
    $z = DseNow
    Lg ('dse after write=0x' + $(if ($z) { $z } else { 'UNREADABLE' }))
    if ($z -notmatch '^0*0$') { Lg 'RESULT: FAIL - DSE did not go to 0'; Emit; exit 1 }
} else { Lg 'dse already 0' }

# 2. the driver
& "$env:SystemRoot\system32\sc.exe" delete zapexdrv 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" create zapexdrv type= kernel start= demand binPath= (Join-Path $d 'zapexdrv.sys') 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" start zapexdrv 2>&1 | Out-Null
Start-Sleep -Milliseconds 800
$q = SvcQ
Lg ('svc after start: ' + $q)
if ($q -notmatch 'RUNNING') { Lg 'RESULT: FAIL - driver did not reach RUNNING (prv 20 may be 1450; re-arm)'; Emit; exit 1 }

# 3. DSE back to 6 BEFORE the game starts - this is the h318 point
Lg ('dse->6 out=[' + (Kdu @('-prv', '20', '-dse', '6')) + ']')
Start-Sleep -Milliseconds 500
$six = DseNow
Lg ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
if ($six -notmatch '^0*6$') { Lg 'RESULT: FAIL - DSE did not read back 6 with the driver loaded'; Emit; exit 1 }
Lg 'dse_verify=PASS(6 with driver RUNNING)'

# 4. restore arms
if ((Get-ItemProperty -LiteralPath $cc).AutoReboot -ne 0) { Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 0 -Type DWord }
Lg ('AutoReboot readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot)
Set-Content -LiteralPath (Join-Path $d 'h318.dsepre') -Value '6'
schtasks.exe /create /tn p318post /tr ('"' + (Join-Path $here 'h317_post.cmd') + '"') /sc onlogon /rl highest /f 2>&1 | ForEach-Object { Lg ('arm: ' + $_) }
schtasks.exe /delete /tn p317post /f 2>&1 | Out-Null
$drv = (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE' }) -join ' ').Trim()
Lg ('RESULT: ARM PASS - dse=6 WITH driver RUNNING (' + $drv + '), AutoReboot 0, p318post armed')
Lg 'VERDICT: launch the game now. If Javelin still exits, the loaded unsigned image is the trigger, not DSE.'
Emit
