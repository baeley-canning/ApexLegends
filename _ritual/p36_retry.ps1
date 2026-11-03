# p36_retry.ps1 - crash-resilient driver for p36_write.ps1, run by task QwenKern_p36.
#
# Death modes seen 02/11/2026:
#   (1) tool-console teardown kills ATTACHED launches      -> task ownership fixes this;
#   (2) bugcheck 0x3B at some phys holes reboots the box  -> the task's logon trigger
#       relaunches this wrapper after every reboot; p36_write.ps1's BADPA learner then
#       blacklists the PA the dying run's io breadcrumbs stop at, so each crash makes
#       the next sweep go FURTHER (crash-learned convergence);
#   (3) rare silent child death without a bugcheck          -> in-invocation retry loop.
# Stops cleanly once p36_write.txt carries the END/ABORT marker, so later logons idle.
$root   = $PSScriptRoot
$w      = Join-Path $root 'p36_write.ps1'
$rlog   = Join-Path $root '_p36_retry.log'
$out    = Join-Path $root 'p36_write.txt'
$bad    = Join-Path $root 'p36_badpa.txt'
function RLog([string]$s) {
    try { Add-Content -LiteralPath $rlog -Value ("{0} {1}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'), $s) -Encoding UTF8 } catch {}
}
RLog ("wrapper start pid={0}" -f $PID)

# ---- done check: a completed probe must not re-run on every logon --------------
try { $cur = [string](Get-Content -LiteralPath $out -Raw -EA 0) } catch { $cur = '' }
if ($cur -match '-- p36 (END|ABORT)') { RLog 'previous run ENDed/ABORTed - nothing to do'; exit 0 }

# ---- keep p36_badpa.txt sane ---------------------------------------------------
# 02/11: the OneDrive-synced badpa file was observed as all-NUL with the right
# length after a run wrote it.  An empty blacklist would make the sweep re-read a
# known hole and bugcheck the box again.  Merge the known holes back in whenever
# the file is missing entries (union is idempotent).
$seed = @('1000000000-1000001000','800000-a00000','2e00000-3000000','4400000-4600000')
try { $have = @(Get-Content -LiteralPath $bad -EA 0 | Where-Object { $_ -match '^\s*[0-9a-f]+\s*-\s*[0-9a-f]+\s*$' }) } catch { $have = @() }
$all = @($seed + $have | Select-Object -Unique)
if (($all -join ',') -ne ($have -join ',')) {
    try {
        ($all -join "`r`n") | Set-Content -LiteralPath $bad -Encoding ascii
        RLog ('badpa seeded/merged -> ' + ($all -join ','))
    } catch { RLog ('badpa reseed FAILED: ' + $_.Exception.Message) }
}

# ---- up to 4 attempts per invocation -------------------------------------------
for ($i = 1; $i -le 4; $i++) {
    RLog ("attempt {0} launching p36_write.ps1" -f $i)
    # stderr used to vanish into the task console - capture it: a statement-level
    # uncaught exception (e.g. a [P36Prov] call aborting the try3 foreach) prints
    # file:line there and nowhere else.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $w 2>> (Join-Path $root '_p36_stderr.txt') | Out-Null
    $rc = $LASTEXITCODE
    RLog ("attempt {0} exited rc={1}" -f $i, $rc)
    try { $cur = [string](Get-Content -LiteralPath $out -Raw -EA 0) } catch { $cur = '' }
    if ($cur -match '-- p36 (END|ABORT)') { RLog 'END/ABORT marker seen - done'; exit $rc }
    if ($i -lt 4) { Start-Sleep -Seconds 20 }
}
RLog 'all attempts exhausted without END'
exit 1