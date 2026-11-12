# mk20_diff.ps1 - two reads of the fixed candidate list, 0.8 s apart: the live view
# changes, stored transforms do not.  Read-only.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $dir 'mk20_diff.txt'
Set-Location -LiteralPath $dir
Set-Content -LiteralPath $log -Value ('# diff start {0:HH:mm:ss} elevated={1}' -f (Get-Date), (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
& python -u (Join-Path $dir '_mk20.py') '--diff' *>> $log
Add-Content -LiteralPath $log -Value ('# diff rc={0} end {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))
