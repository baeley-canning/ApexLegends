# h310 dseprobe - which literal kdu argument spellings actually parse? Elevated, writes/reads
# nothing except the DSE flag. Writes every raw output to one file so the next script can copy the
# spelling that works instead of guessing again.
$out = 'C:\Users\Public\p37\h310_dseprobe.txt'
Set-Content -LiteralPath $out -Value ('===== ' + (Get-Date -f 'HH:mm:ss') + ' =====')
$kdu = 'C:\Users\Public\p37\kdu.exe'
$tests = @(
    '-prv 0 -dse 6',
    '-prv 0 -dse 0',
    '-dse 6 -prv 0',
    '-prv 1 -dse 6'
)
foreach ($t in $tests) {
    $f = New-Object System.Diagnostics.ProcessStartInfo
    $f.FileName = $kdu; $f.Arguments = $t; $f.WorkingDirectory = 'C:\Users\Public\p37'
    $f.RedirectStandardOutput = $true; $f.RedirectStandardError = $true; $f.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($f)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    [void]$p.WaitForExit(60000)
    $txt = (($so.Result + ' ' + $se.Result) -replace '\s+', ' ')
    $hit = if ($txt -match 'DSE flags[^\[\]]{0,80}') { $matches[0] } else { '(no DSE flags line)' }
    Add-Content -LiteralPath $out -Value ($t + ' => ' + $hit)
}
Add-Content -LiteralPath $out -Value 'state: done'
