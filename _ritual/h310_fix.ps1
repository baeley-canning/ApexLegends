# h310 fix - the h310_post run at 18:19 proved nothing: kdu's stdout was thrown away (missing
# UseShellExecute=$false), so 'dse_verify=FAIL' was a harness artefact, not a DSE reading, and the
# same applies to finding the dump under the ACL on C:\Windows\Minidump. This does both properly:
# locate the dump, then read DSE and put it back to 6 with a read-back. Idempotent.
$ErrorActionPreference = 'Continue'
$out = 'C:\Users\Public\p37\h310_dse.txt'
function Say([string]$s) { $l = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Write-Host $l; Add-Content -LiteralPath $out -Value $l -EA 0 }
Say ('===== h310 fix ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')

$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Say ('boot=' + $boot.ToString('dd/MM HH:mm:ss'))
Say 'minidump dir:'
$all = @(Get-ChildItem 'C:\Windows\Minidump\*.dmp' -Force -EA 0 | Sort-Object LastWriteTime)
if ($all.Count) { foreach ($f in $all) { Say ('  ' + $f.Name + ' ' + $f.Length + ' ' + $f.LastWriteTime.ToString('dd/MM HH:mm:ss')) } } else { Say '  (none visible)' }
$mem = Get-Item 'C:\Windows\MEMORY.DMP' -Force -EA 0
Say ('MEMORY.DMP: ' + $(if ($mem) { 'yes ' + $mem.Length + ' ' + $mem.LastWriteTime.ToString('dd/MM HH:mm:ss') } else { 'absent' }))
$fresh = @($all | Where-Object { $_.LastWriteTime -gt $boot.AddMinutes(-90) })
Say ('fresh (post-boot-90min) minidumps=' + $fresh.Count)

$kdu = 'C:\Users\Public\p37\kdu.exe'
function Kdu([string[]]$a) {
    $f = New-Object System.Diagnostics.ProcessStartInfo
    $f.FileName = $kdu; $f.RedirectStandardOutput = $true; $f.RedirectStandardError = $true; $f.UseShellExecute = $false
    # Windows PowerShell 5.1 has no ProcessStartInfo.ArgumentList; build a string instead (kdu
    # otherwise runs with no arguments and answers with its usage text).
    $f.WorkingDirectory = Split-Path -Parent $kdu
    $f.Arguments = (($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $p = [System.Diagnostics.Process]::Start($f)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    [void]$p.WaitForExit(60000)
    return (((($so.Result + ' ' + $se.Result) -replace '\s+', ' ')).Trim())
}
$pre = Kdu @('-prv', '22', '-dse')
Say ('dse read: [' + $pre + ']')
if ($pre -match '0x0*6' -or $pre -match '= *6\b' -or ($pre -match 'DSE' -and $pre -notmatch '0x0*0\b')) {
    Say 'DSE already 6, nothing to write'
} else {
    Say ('dse write: [' + (Kdu @('-prv', '22', '-dse', '6')) + ']')
    $post = Kdu @('-prv', '22', '-dse')
    Say ('dse readback: [' + $post + ']')
    if ($post -match '0x0*6' -or $post -match '= *6\b') { Say 'RESULT: PASS - DSE back to 6' } else { Say 'RESULT: FAIL - DSE readback does not show 6' }
}
Say 'state: done'
