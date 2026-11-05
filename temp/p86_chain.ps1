# p86_chain.ps1 -- one RUN slot: refresh live EPROCESS/DTB (p85) then immediately
# sweep the IOCTL shapes (p84) against them. Exists because the pid that p85 picks can
# die between two separate RUN slots (1688 died 09:07 -> 09:10 with p84 still pending).
# Own stamp-suffixed log per R5; p84 is skipped unless p85 says TARGETS_OK.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Location -LiteralPath $repo
$stamp = Get-Date -Format 'HHmmss'
$log = Join-Path $repo ("temp\_p86_chain_$stamp.txt")
function L([string]$t) { ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $t) | Out-File -Append -Encoding utf8 $log }
"=== p86_chain $stamp ===" | Set-Content -Encoding utf8 $log
L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

Remove-Item -LiteralPath (Join-Path $repo 'temp\_p85_refresh.txt'), (Join-Path $repo 'temp\_p85_targets.txt'), (Join-Path $repo 'temp\_p84_ioctl_shapes.txt') -EA 0

L 'step 1: p85_refresh'
& python -u (Join-Path $repo 'temp\p85_refresh.py') *> (Join-Path $repo 'temp\p85_console.txt')
$r85 = $LASTEXITCODE
L ("p85 rc=$r85")
$verdict = (Select-String -Path (Join-Path $repo 'temp\_p85_refresh.txt') -Pattern 'VERDICT:' -EA 0 | Select-Object -Last 1).Line
L ("p85 verdict: " + $verdict)
if ($verdict -notmatch 'TARGETS_OK') {
    L 'RESULT skipped p84: no live targets'
    L 'VERDICT: CHAIN_NO_TARGETS'
    L 'p86 end'
    exit 4
}

$t = Get-Content -LiteralPath (Join-Path $repo 'temp\_p85_targets.txt') -EA 0
$ctl = ($t | Where-Object { $_ -match '^CTL=' } | Select-Object -First 1) -replace '^CTL=', ''
$bad = ($t | Where-Object { $_ -match '^BAD=' } | Select-Object -First 1) -replace '^BAD=', ''
$pid85 = ($t | Where-Object { $_ -match '^PID=' } | Select-Object -First 1) -replace '^PID=', ''
$alive = [bool](Get-Process -Id $pid85 -EA 0)
L ("targets ctl=$ctl bad=$bad pid=$pid85 alive_at_step2=$alive")
if (-not $ctl -or -not $bad) {
    L 'RESULT missing ctl/bad in targets file'
    L 'VERDICT: CHAIN_BAD_TARGETS'
    L 'p86 end'
    exit 5
}

L 'step 2: p84_ioctl_shapes'
& python -u (Join-Path $repo 'temp\p84_ioctl_shapes.py') $ctl $bad *> (Join-Path $repo 'temp\p84_console.txt')
$r84 = $LASTEXITCODE
L ("p84 rc=$r84")
$v84 = (Select-String -Path (Join-Path $repo 'temp\_p84_ioctl_shapes.txt') -Pattern 'VERDICT:|RESULT ' -EA 0 | ForEach-Object { $_.Line }) -join ' | '
L ("p84 says: " + $v84)
L ("RESULT p85_rc=$r85 p84_rc=$r84 ctl=$ctl bad=$bad")
L ("VERDICT: CHAIN_RAN p84_rc=$r84")
L 'p86 end'
exit $r84
