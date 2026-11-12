# _h307_go.ps1 - parse-check then launch h307_elev.ps1 hidden; prints parse_errors and pid.
$f = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h307_elev.ps1'
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
Set-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h307_parse.txt' -Value ('parse_errors=' + @($e).Count) -Encoding ascii
if (@($e).Count -eq 0) {
    $p = Start-Process 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"') -WindowStyle Hidden -PassThru
    Add-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h307_parse.txt' -Value ('pid=' + $p.Id) -Encoding ascii
}
Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h307_parse.txt'

