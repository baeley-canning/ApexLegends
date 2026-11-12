# mk20_run.ps1 - one elevated pass of _mk20.py.  Read-only: gdrv3 physical reads,
# writes only temp\_mk20_out.txt / _mk20_raw.txt / _mk20_rects.txt.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $dir 'mk20_console.txt'
Set-Location -LiteralPath $dir
Set-Content -LiteralPath $log -Value ('# mk20_run start {0:HH:mm:ss} elevated={1}' -f (Get-Date), (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
& python -u (Join-Path $dir '_mk20.py') --probe *>> $log
$rc = $LASTEXITCODE
Add-Content -LiteralPath $log -Value ('# mk20_run rc={0} end {1:HH:mm:ss}' -f $rc, (Get-Date))
