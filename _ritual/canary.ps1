# canary.ps1 -- prove that an elevated child, launched by Start-Process -Verb RunAs, can run AND write
# to both C:\Windows\Temp and its own script dir.  Writes status only; changes nothing.
$d = $PSScriptRoot
$lines = @(
    'pid=' + $PID
    'user=' + [Environment]::UserName
    'elev=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    'cwd=' + (Get-Location).Path
    'scriptroot=[' + $d + ']'
    'scriptroot-exists=' + (Test-Path -LiteralPath $d)
    'psver=' + $PSVersionTable.PSVersion.ToString()
)
try { ($lines -join "`r`n") | Set-Content -LiteralPath 'C:\Windows\Temp\p26canary.txt' -Encoding ascii } catch {
    ($lines + ('TEMP-WRITE-FAIL=' + $_.Exception.Message)) -join "`r`n" | Out-File -LiteralPath 'C:\p26canary.txt' -Encoding ascii
}
try {
    ($lines -join "`r`n") | Set-Content -LiteralPath (Join-Path $d 'canary.txt') -Encoding ascii
    'here-write=ok' | Add-Content -LiteralPath 'C:\Windows\Temp\p26canary.txt' -Encoding ascii
} catch { ('here-write-fail=' + $_.Exception.Message) | Add-Content -LiteralPath 'C:\Windows\Temp\p26canary.txt' -Encoding ascii }
