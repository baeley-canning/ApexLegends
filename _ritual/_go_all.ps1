param([switch]$ElevatedChild)

# one-shot: h413 baseline, then h414 .data scan. Each probe runs in its own process so the
# two Add-Type class definitions cannot collide. Re-launches itself elevated because
# SeDebugPrivilege cannot be assigned to an unelevated token (SetDebugPrivilege -> 1300,
# OpenProcess(0x0410) -> 5).
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$res = "$dir\_go_result.txt"

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr  = New-Object Security.Principal.WindowsPrincipal($id)
$adm = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# psapi truncates module bases to 32 bits when the caller is WOW64, so every child
# is pinned to the real 64-bit host (Sysnative from a 32-bit parent).
$caller64 = [Environment]::Is64BitProcess
$ps64 = if ($caller64) { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
        else { "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }

if (-not $adm -and -not $ElevatedChild) {
    Remove-Item -LiteralPath $res -ErrorAction SilentlyContinue
    "raising UAC at $(Get-Date -Format s) pid=$PID caller64=$caller64" | Out-File -LiteralPath $res -Encoding ascii
    try {
        Start-Process -FilePath $ps64 -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ElevatedChild'
        )
        "uac launched, parent not waiting" | Add-Content -LiteralPath $res -Encoding ascii
    } catch {
        ("uac FAILED: " + $_.Exception.Message) | Add-Content -LiteralPath $res -Encoding ascii
    }
    exit
}

$lines = New-Object System.Collections.ArrayList
function Say($s) { [void]$lines.Add([string]$s) }
function Flush { $lines -join "`r`n" | Out-File -LiteralPath $res -Encoding ascii }

"elevated=$adm caller64=$caller64" | Out-File -LiteralPath $res -Encoding ascii
if (-not $adm) { Say 'ERROR: elevation did not stick'; Flush; exit }

$tag = Get-Date -Format 'yyyyMMdd_HHmmss'
$p = Get-Process -Name 'r5apex_dx12' -ErrorAction SilentlyContinue
if (-not $p) { Say "NO_GAME at $tag - launch Apex and join the Firing Range first"; Flush; exit 1 }
Say "game pid $($p[0].Id) at $tag"

Remove-Item -LiteralPath "$dir\_h413_out.txt", "$dir\_h413_rc.txt", "$dir\_h414_out.txt", "$dir\_h414_rc.txt", "$dir\_h415_out.txt", "$dir\_h416_out.txt" -ErrorAction SilentlyContinue
$t0 = Get-Date

& $ps64 -NoProfile -ExecutionPolicy Bypass -File "$dir\_h413_probe.ps1" | Out-Null
Say ("h413 rc = " + ((Get-Content -LiteralPath "$dir\_h413_rc.txt" -ErrorAction SilentlyContinue) -join ' '))

& $ps64 -NoProfile -ExecutionPolicy Bypass -File "$dir\_h414_scan.ps1" | Out-Null
Say ("h414 rc = " + ((Get-Content -LiteralPath "$dir\_h414_rc.txt" -ErrorAction SilentlyContinue) -join ' '))

& $ps64 -NoProfile -ExecutionPolicy Bypass -File "$dir\_h416_shape.ps1" | Out-Null
Say '--- h416 ---'; Get-Content -LiteralPath "$dir\_h416_out.txt" -ErrorAction SilentlyContinue | ForEach-Object { Say $_ }

Say ("elapsed = " + [int]((Get-Date) - $t0).TotalSeconds + "s")
Say '--- h413 ---'; Get-Content -LiteralPath "$dir\_h413_out.txt" -ErrorAction SilentlyContinue | ForEach-Object { Say $_ }
Say '--- h414 ---'; Get-Content -LiteralPath "$dir\_h414_out.txt" -ErrorAction SilentlyContinue | ForEach-Object { Say $_ }
Flush
