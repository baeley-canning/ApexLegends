# h318_reload.ps1 - load the v13 driver again after the mid-session swap killed the game.
# Javelin's rule holds: DSE 0 for the length of the start, then straight back to the boot byte 0x16,
# driver left RUNNING so the next game start sees the gate-proven condition (driver resident, DSE on).
# R3: gates on svc state and on the DSE read-back. Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_reload.out'
$d    = 'C:\Users\Public\p37'
$sys  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
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
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
Lg '===== h318 reload v14 ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=' + (SvcQ) + ' drv sha=' + (Get-FileHash $sys -Algorithm SHA256).Hash.Substring(0, 16))
if ((Get-FileHash $sys -Algorithm SHA256).Hash -ne '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C') { Lg 'RESULT: FAIL - staged image is not the v14 build'; Emit; exit 1 }
# DSE must be 0 for the start
$o = Kdu @('-prv', '20', '-dse'); $pre = if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
if ($pre -notmatch '^0*0$') { Lg ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']'); Start-Sleep -Milliseconds 400 }
& "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" create apexdrv type= kernel start= demand binPath= $sys 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
Start-Sleep -Seconds 2
$q = SvcQ
Lg ('svc after start: ' + $q)
if ($q -notmatch 'RUNNING') { Lg 'RESULT: FAIL - v14 did not start (DSE/1450)'; Emit; exit 1 }
Lg ('dse->22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']')
Start-Sleep -Milliseconds 400
$c2 = Kdu @('-prv', '20', '-dse', '22'); $six = if ($c2 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
if ($six -match '^0*16$') { Lg 'RESULT: PASS - v14 RUNNING, dse 0x16 verified - relaunch the game now'; Emit; exit 0 }
Lg ('RESULT: FAIL - dse not back at 0x16 (0x' + $six + ')'); Emit; exit 1
