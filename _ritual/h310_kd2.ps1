# h310 kd2 - analysis pass on the minidump the 18:04 bugcheck actually left behind
# (110626-9968-01.dmp; event 1001 named it, MEMORY.DMP was never created). Elevation needed both
# for the ACL on C:\Windows\Minidump and for the symbol cache. Read-only: copies the dump out, no state.
$ErrorActionPreference = 'Continue'
$pub = 'C:\Users\Public\p37'
$out = Join-Path $pub 'h310_kd.txt'
function Say([string]$s) { $l = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Write-Host $l; Add-Content -LiteralPath $out -Value $l -EA 0 }
Say ('===== h310 kd2 ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')

$src = 'C:\Windows\Minidump\110626-9968-01.dmp'
$work = Join-Path $pub 'h310_mini.dmp'
Copy-Item -LiteralPath $src -Destination $work -Force -EA 0
$i = Get-Item $work -EA 0
Say ('dump=' + $work + ' size=' + $(if ($i) { $i.Length } else { 0 }) + ' src-write=' + (Get-Item $src).LastWriteTime.ToString('dd/MM HH:mm:ss'))

# DSE after the reboot: g_CiOptions is runtime memory and does not survive, so expect 6 - confirm.
$kdu = Join-Path $pub 'kdu.exe'
function Kdu([string[]]$a) {
    $f = New-Object System.Diagnostics.ProcessStartInfo
    $f.FileName = $kdu; $f.Arguments = ($a -join ' '); $f.RedirectStandardOutput = $true
    $f.RedirectStandardError = $true; $f.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($f)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch { } }
    return ((($so.Result + ' ' + $se.Result) -replace '\s+', ' ').Trim())
}
$dd = Kdu @('-prv', '22', '-dse')
Say ('dse now: [' + $(if ($dd -match '(value|state)[^\]]*') { $matches[0] } else { $dd.Substring([Math]::Max(0, $dd.Length - 200)) }) + ']')
# 0x16 means DSE is still off from the probe; the crash killed the process before its own restore.
if ($dd -notmatch 'value:\s*6\b') {
    $dw = (Kdu @('-prv', '22', '-dse', '6') -replace '\s+', ' ').Trim()
    Say ('dse write 6: [...' + $dw.Substring([Math]::Max(0, $dw.Length - 160)) + ']')
    $dr = Kdu @('-prv', '22', '-dse')
    Say ('dse readback: [' + $(if ($dr -match 'value:\s*[0-9A-Fa-f]+') { $matches[0] } else { 'no value' }) + ']')
    Say ('dse_verify=' + $(if ($dr -match 'value:\s*0*6\b') { 'PASS' } else { 'FAIL' }))
} else { Say 'dse_verify=PASS (already 6)' }

$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
if (-not (Test-Path $kd)) { Say 'RESULT: FAIL - kd.exe missing'; exit 1 }
# kd 26100 gives -i a required argument, so the bare '-i' used in h310_post eats '-z' and errors out.
$argline = '-y C:\symbols -z "' + $work + '" -c ".symopt- 100; !analyze -v; r; kb; lm; q"'
Say ('kd ' + $argline)
$f = New-Object System.Diagnostics.ProcessStartInfo
$f.FileName = $kd; $f.Arguments = $argline; $f.RedirectStandardOutput = $true
$f.RedirectStandardError = $true; $f.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($f)
$so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(300000)) { try { $p.Kill() } catch { } ; Say 'kd timed out at 300s' }
$txt = ($so.Result + "`n" + $se.Result)
$raw = Join-Path $pub 'h310_kd_raw.txt'
Set-Content -LiteralPath $raw -Value $txt -Encoding UTF8
Say ('kd rc=' + $p.ExitCode + ' bytes=' + $txt.Length + ' raw=' + $raw)
Say 'done - see h310_kd_raw.txt'
