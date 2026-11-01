$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'p25b.ps1'),[ref]$null,[ref]$e)
if($e){ 'PARSE ERRORS in p25b.ps1:'; $e | ForEach-Object { '  ' + $_.Message } } else { 'PARSE OK p25b.ps1' }
'--- leftover probe artifacts from p25 (to be swept later):'
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match 'ApexDrv' } | ForEach-Object { '  My  ' + $_.Thumbprint + '  ' + $_.Subject }
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match 'ApexDrv' } | ForEach-Object { '  Root ' + $_.Subject }
'--- kernprobe now:'
(& sc.exe query kernprobe 2>&1) -join ' '
