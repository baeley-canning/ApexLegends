$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'p25d.ps1'),[ref]$null,[ref]$e)
if($e){ 'PARSE ERRORS in p25d.ps1:'; $e | ForEach-Object { '  line ' + $_.Extent.StartLineNumber + ': ' + $_.Message } } else { 'PARSE OK p25d.ps1' }
'lines = ' + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'p25d.ps1')).Count
'KeyUsages enum names: ' + ([System.Enum]::GetNames([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]) -join ',')
'signtool findable: ' + (Test-Path 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe')
