# h329_dse_park.ps1 - put g_CiOptions back to the boot byte 0x16 and prove it with a read-back.
# Exists because kdu's bare `-dse` is read-AND-write-0 (the h318 trap): h329_fire_readonly's
# pre-flight used it on 07/11 20:02 and left DSE 0 - and "leaving 0 gets Security Violation (2) -
# signing integrity checks must be enabled at game start" (HANDOFF_h318). Park form: `-dse 22`
# prints the CURRENT value first, then writes 22, so one call both reads and parks; a second
# call is the R3 read-back. No service change, no driver reload, safe to re-run. Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h329_dse_park.out'
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
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
Lg '===== h329 dse park (g_CiOptions -> boot byte 0x16) ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=[' + (SvcQ) + ']')
$o1 = Kdu @('-prv', '20', '-dse', '22'); $cur = if ($o1 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { 'UNREADABLE' }
Lg ('current value was 0x' + $cur + ' -> parked to 22')
Start-Sleep -Milliseconds 500
$o2 = Kdu @('-prv', '20', '-dse', '22'); $rb = if ($o2 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { 'UNREADABLE' }
Lg ('read-back value=0x' + $rb)
if ($rb -match '^0*16$') { Lg 'RESULT: PASS - dse 0x16 (game-start gate condition); driver and service untouched'; Emit; exit 0 }
Lg 'RESULT: FAIL - dse not 0x16 after park'; Emit; exit 1
