# h310 dse6 - put DSE back to 6 with the provider that actually works (0 = NAL).
# h310_fix.ps1 used prv 22 and kdu answered "no valid parameters combination" for BOTH the read and
# the write, so its FAIL was a provider artefact, not a DSE reading. prv 0 drove every run.
# Read-back is a second write of the same value: kdu re-reads the flag first and prints
# "value: N, new value to be written: N", so N in the value: field is the observed state.
$out = 'C:\Users\Public\p37\h310_dse6.txt'
function Say([string]$s) { $l = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Write-Host $l; Add-Content -LiteralPath $out -Value $l -EA 0 }
Say ('===== dse6 ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
$kdu = 'C:\Users\Public\p37\kdu.exe'
function Kdu([string[]]$a) {
    $f = New-Object System.Diagnostics.ProcessStartInfo
    $f.FileName = $kdu; $f.RedirectStandardOutput = $true; $f.RedirectStandardError = $true; $f.UseShellExecute = $false
    # kdu loads drv64.dll (its provider database) from its OWN directory - without it every
    # -dse call degrades to "no valid parameters combination" + usage text (19:27 measured).
    $f.WorkingDirectory = 'C:\Users\Public\p37'
    # Windows PowerShell 5.1 has no ProcessStartInfo.ArgumentList (that is .NET Core); $null.Add()
    # fails silently and kdu then runs with NO arguments at all - the usage text was the clue.
    $f.Arguments = (($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $p = [System.Diagnostics.Process]::Start($f)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    [void]$p.WaitForExit(60000)
    return (((($so.Result + ' ' + $se.Result) -replace '\s+', ' ')).Trim())
}
Say ('write 6: [' + (Kdu @('-prv', '0', '-dse', '6')) + ']')
$back = Kdu @('-prv', '0', '-dse', '6')
Say ('readback: [' + $back + ']')
if ($back -match 'DSE flags \([^)]*\)\s*value:\s*([0-9A-Fa-f]+)') {
    # anchor on the "DSE flags (0x...)" prefix: a bare `.*value:` walks into "Return value: 1" at
    # the end of kdu's output and reads the wrong number (19:32 measured).
    $v = $matches[1]
    if ($v -match '^0*6$') { Say ('RESULT: PASS - DSE value: 0x' + $v + ' (6 confirmed by read-back)') }
    else { Say ('RESULT: FAIL - DSE value: 0x' + $v + ', wanted 6') }
} else { Say 'RESULT: FAIL - no DSE flags value: line in the read-back' }
Say 'state: done'
