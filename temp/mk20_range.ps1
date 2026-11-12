# mk20_range.ps1 - firing range, no scan: fresh census, then ONE burst (matrix + records).
# The player must be moving for the census's walk window; the burst itself takes ~10 s.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $dir 'mk20_range.txt'
Set-Location -LiteralPath $dir
Set-Content -LiteralPath $log -Value ('# range start {0:HH:mm:ss} elevated={1}' -f (Get-Date), (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

& python -u (Join-Path $dir '_p134.py') *>> $log
Add-Content -LiteralPath $log -Value ('# census rc={0} {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))

& python -u (Join-Path $dir '_mk20.py') '--probe' *>> $log
Add-Content -LiteralPath $log -Value ('# probe rc={0} end {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))
