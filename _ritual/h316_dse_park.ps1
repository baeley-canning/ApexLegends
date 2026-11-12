# h316_dse_park.ps1 - the h316 run read DSE as 0x0 at 22:08:57 (it was ALREADY off before we touched
# it) and its own restore wrote 0 back, so the host is currently dirty. Park it: read, write 6, read
# back, and leave it alone if it is already 6. prv 20 (DBUtilDrv2) is the provider that answered and
# started the driver in that run, so it is the one used here too.
# R3: pre-read, post-read, verdict only from the read-back. R4: the write is idempotent.
# R5: own output file. Self-elevating (kdu needs admin).
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h316_dse_park.out'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
$kdu = 'C:\Users\Public\p37\kdu.exe'
Lg '===== h316 dse park ====='
Lg ('admin=' + $adm)
function Kdu([string[]]$a) {
    $o = ''; $e = ''
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $kdu; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = 'C:\Users\Public\p37'
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch { } }
          $o = $t1.Result; $e = $t2.Result } catch { $e = $_.Exception.Message }
    return ($o + $e)
}
$pre = ''
foreach ($id in 20, 16, 17) {
    $r = Kdu @('-prv', "$id", '-dse')
    if ($r -match 'value:\s*([0-9A-Fa-f]+)') { $pre = $matches[1]; Lg ('pre read via prv ' + $id + ' = 0x' + $pre); break }
    Lg ('pre read prv ' + $id + ' no value')
}
if ($pre -eq '') { Lg 'RESULT: FAIL - DSE unreadable, nothing written'; Emit; exit 1 }
if ($pre -match '^0*6$') { Lg 'DSE already 6 - left alone'; Lg ('RESULT: PASS - dse=0x' + $pre + ' (already parked)'); Emit; exit 0 }
$w = Kdu @('-prv', '20', '-dse', '6')
Lg ('write out=[' + (($w -replace '\s+', ' ').Trim()) + ']')
Start-Sleep -Seconds 1
$post = ''
foreach ($id in 20, 16, 17) {
    $r = Kdu @('-prv', "$id", '-dse')
    if ($r -match 'value:\s*([0-9A-Fa-f]+)') { $post = $matches[1]; break }
}
Lg ('post read=0x' + $(if ($post) { $post } else { 'UNREADABLE' }))
if ($post -match '^0*6$') { Lg ('RESULT: PASS - dse 0x' + $pre + ' -> 0x' + $post + ' (parked)'); Emit; exit 0 }
Lg ('RESULT: FAIL - dse 0x' + $pre + ' -> 0x' + $(if ($post) { $post } else { 'UNREADABLE' }) + ', still not 6')
Emit
exit 1
