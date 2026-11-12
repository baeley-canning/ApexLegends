# mk20_ram.ps1 - one RAM pass for world->view matrices, scored against the current
# census.  Read-only; no walking, no turning, no driver.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $dir 'mk20_ram.txt'
Set-Location -LiteralPath $dir
Set-Content -LiteralPath $log -Value ('# ramscan start {0:HH:mm:ss} elevated={1}' -f (Get-Date), (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
& python -u (Join-Path $dir '_mk20.py') '--ramscan' *>> $log
Add-Content -LiteralPath $log -Value ('# ramscan rc={0} end {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))
