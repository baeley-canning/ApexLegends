$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'p25c.ps1'),[ref]$null,[ref]$e)
if($e){ 'PARSE ERRORS in p25c.ps1:'; $e | ForEach-Object { '  line ' + $_.Extent.StartLineNumber + ': ' + $_.Message } } else { 'PARSE OK p25c.ps1' }
'lines = ' + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'p25c.ps1')).Count
'kernprobe now: ' + (((& sc.exe query kernprobe 2>&1) -join ' ') -replace '\s+',' ')
