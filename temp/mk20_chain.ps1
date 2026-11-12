# mk20_chain.ps1 - one sitting: find candidate matrix RVAs in the image, take a fresh
# census, then read the matrix candidates and the census records in the SAME burst.
# Read-only on the OS; writes only inside temp\.
$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $dir 'mk20_chain.txt'
Set-Location -LiteralPath $dir
Set-Content -LiteralPath $log -Value ('# chain start {0:HH:mm:ss} elevated={1}' -f (Get-Date), (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

& python -u (Join-Path $dir '_mk20.py') '--scan' *>> $log
Add-Content -LiteralPath $log -Value ('# scan rc={0} {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))

& python -u (Join-Path $dir '_p134.py') *>> $log
Add-Content -LiteralPath $log -Value ('# census rc={0} {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))

& python -u (Join-Path $dir '_mk20.py') '--probe' *>> $log
Add-Content -LiteralPath $log -Value ('# probe rc={0} end {1:HH:mm:ss}' -f $LASTEXITCODE, (Get-Date))
