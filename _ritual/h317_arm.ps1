# h317_arm.ps1 - step 1 of the split h317 (h316 proved Javelin exits the game ~10 s into a full chain).
# Arms the kernel side with the game NOT running: DSE 0 via prv 20 ONLY (the provider that read 6 back
# correctly and started the driver at 22:09), start zapexdrv, verify RUNNING, then LEAVE IT ARMED.
# The restore is h317post (logon task, armed here) + h317_teardown.ps1 for a clean run.
# R3: DSE read, write, read-back, service state - verdict only from the read-backs.
# R5: own files (h317_arm.out, h317.dsepre). Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h317_arm.out'
$d    = 'C:\Users\Public\p37'
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
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('LAUNCH FAIL ' + $_.Exception.Message) }
}
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
Lg '===== h317 arm ====='
Lg ('admin=' + $adm + ' boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s'))
Lg ('game now=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' (must be 0 for a clean arm)')
Lg ('pre svc: ' + (SvcQ))

# --- DSE: one provider, full output kept (h316's sweep threw its value lines away) -------------
$pre = ''
$o = Kdu @('-prv', '20', '-dse')
Lg ('pre read out=[' + $o + ']')
if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $pre = $matches[1] } 
if ($pre -eq '') { Lg 'RESULT: FAIL - DSE unreadable via prv 20, nothing armed'; Emit; exit 1 }
$preDec = [Convert]::ToInt32($pre, 16)
Lg ('dse_pre=0x' + $pre + ' (decimal ' + $preDec + ')')
Set-Content -LiteralPath (Join-Path $d 'h317.dsepre') -Value $preDec
if ($preDec -ne 0) {
    $w = Kdu @('-prv', '20', '-dse', '0')
    Lg ('write out=[' + $w + ']')
    Start-Sleep -Milliseconds 500
    $chk = Kdu @('-prv', '20', '-dse')
    Lg ('post-write read=[' + $chk + ']')
    if ($chk -notmatch 'value:\s*0*0\b') { Lg 'RESULT: FAIL - DSE did not read back 0 after the write'; Emit; exit 1 }
    Lg 'dse_verify=0 CONFIRMED'
} else { Lg 'dse already 0, no write' }

# --- driver up, and it MUST stay up -----------------------------------------------------------
& "$env:SystemRoot\system32\sc.exe" delete zapexdrv 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" create zapexdrv type= kernel start= demand binPath= (Join-Path $d 'zapexdrv.sys') 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" start zapexdrv 2>&1 | Out-Null
Start-Sleep -Milliseconds 800
$q = SvcQ
Lg ('svc after start: ' + $q)
if ($q -notmatch 'RUNNING') { Lg 'RESULT: FAIL - zapexdrv did not reach RUNNING (retry the arm; prv 20 may be transiently 1450)'; Emit; exit 1 }

# --- host-level restore arms ------------------------------------------------------------------
$cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
if ((Get-ItemProperty -LiteralPath $cc).AutoReboot -ne 0) {
    Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 0 -Type DWord
    Lg ('AutoReboot 0, readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot)
} else { Lg 'AutoReboot already 0' }
schtasks.exe /create /tn p317post /tr ('"' + (Join-Path $here 'h317_post.cmd') + '"') /sc onlogon /rl highest /f 2>&1 | ForEach-Object { Lg ('arm: ' + $_) }
Lg ('arm readback: ' + ((schtasks.exe /query /tn p317post 2>&1) -join ' '))
Lg ('RESULT: ARM PASS - dse=0 (read-back), zapexdrv RUNNING, dse_pre stored ' + $preDec)
Lg 'VERDICT: armed against a running game - launch Apex NOW, then h317_inject.ps1. Driver is intentionally left RUNNING.'
Emit
