# snap_run.ps1 - elevated one-pass dump for _mk19 --snap.  Read-only on the OS,
# writes only inside temp\dump\.  Launched detached (see snap_launch.txt) because
# polling the console from the agent shell kills the child mid-scan.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $dir 'snap_console.txt'
Set-Location -LiteralPath $dir
Set-Content -LiteralPath $log -Value ('# snap_run start {0:HH:mm:ss}  elevated={1}' -f (Get-Date), (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
& python (Join-Path $dir '_mk19.py') --snap *>> $log
$rc = $LASTEXITCODE
Add-Content -LiteralPath $log -Value ('# snap_run rc={0} end {1:HH:mm:ss}' -f $rc, (Get-Date))
