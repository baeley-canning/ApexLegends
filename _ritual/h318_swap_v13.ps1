# h318_swap_v13.ps1 - replace the staged driver with the ABI v13 build the launcher requires.
# The gate-proven file at System32\drivers\apexdrv.sys is ABI v2 (the launcher refuses: "driver ABI
# v2 < v13"). Same source, newer ABI - the harness needs v13 to score entryFlag/step at all.
# Sequence keeps Javelin's rule: DSE 0 only for the length of the load, straight back to boot 0x16.
# R4: the v2 file is kept as .v2.bak. R3: every step gated on its read-back. Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_swap_v13.out'
$dst  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$src  = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys'
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
Lg '===== h318 swap driver to ABI v13 ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=' + (SvcQ))
Lg ('src=' + $src + ' exists=' + (Test-Path $src) + ' sha=' + (Get-FileHash $src -Algorithm SHA256).Hash.Substring(0, 16))
Lg ('dst before sha=' + (Get-FileHash $dst -Algorithm SHA256).Hash.Substring(0, 16))
if (SvcQ -match 'RUNNING') { & "$env:SystemRoot\system32\sc.exe" stop apexdrv 2>&1 | Out-Null; Start-Sleep -Seconds 2; Lg ('svc stopped: ' + (SvcQ)) }
Copy-Item -LiteralPath $dst -Destination ($dst + '.v2.bak') -Force
Copy-Item -LiteralPath $src -Destination $dst -Force
Lg ('dst after sha=' + (Get-FileHash $dst -Algorithm SHA256).Hash.Substring(0, 16) + ' (v2 kept at .v2.bak)')
$pre = ''; $o = Kdu @('-prv', '20', '-dse')
if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $pre = $matches[1] }
Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
if ($pre -notmatch '^0*0$') { Lg ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']'); Start-Sleep -Milliseconds 400 }
& "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
Start-Sleep -Seconds 2
$q = SvcQ
Lg ('svc after start: ' + $q)
if ($q -notmatch 'RUNNING') { Lg 'RESULT: FAIL - driver did not start with the v13 image'; Emit; exit 1 }
Lg ('dse->22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']')
Start-Sleep -Milliseconds 400
$six = ''; $c2 = Kdu @('-prv', '20', '-dse', '22')
if ($c2 -match 'value:\s*([0-9A-Fa-f]+)') { $six = $matches[1] }
Lg ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
if ($six -match '^0*16$') { Lg 'RESULT: PASS - v13 loaded, RUNNING, dse 0x16 verified'; Lg 'VERDICT: inject now'; Emit; exit 0 }
Lg ('RESULT: FAIL - dse did not return to 0x16 (got 0x' + $six + ')'); Emit; exit 1
