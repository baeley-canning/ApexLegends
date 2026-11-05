$target = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h275_cur.ps1'
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$null, [ref]$errs)
$out = Join-Path $PSScriptRoot '_syntax_h275.txt'
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message } | Out-File $out -Encoding utf8 }
else { 'SYNTAX OK' | Out-File $out -Encoding utf8 }
