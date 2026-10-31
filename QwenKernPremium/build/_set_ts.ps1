# ============================================================================
# build\_set_ts.ps1  - ELEVATED experiment: does `bcdedit /set testsigning on`
# actually stick?  Sets once, then re-reads {current} and /enum all over 10s so
# a silent revert (or a write that landed on another entry) is visible.
# Output: build\phase1_evidence\_set_ts.txt
# ============================================================================
[CmdletBinding()]
param([switch] $Elevated)

$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev   = Join-Path $root 'build\phase1_evidence'
$log  = Join-Path $ev '_set_ts.txt'
$lock = Join-Path $ev '_set_ts.lock'

function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log; Write-Host $t }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Elevated) { 'FATAL: not elevated' | Out-File -Encoding utf8 -Append $log; exit 2 }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated') | Out-Null
    exit 0
}

# one instance at a time: two racing writers is what muddied the last log
if (Test-Path $lock) {
    $age = (Get-Date) - (Get-Item $lock).LastWriteTime
    if ($age.TotalSeconds -lt 120) { Write-Host 'another instance is running'; exit 3 }
}
'dummy' | Out-File -Encoding utf8 $lock

function Bcd([string] $a) {
    $t = (& cmd /c "bcdedit $a" 2>&1 | Out-String).Trim()
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = $t }
}
function Show([string] $label, $r) {
    W "--- $label EXIT=$($r.Exit) ---"
    foreach ($line in ($r.Text -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
}

"== set testsigning $(Get-Date -Format 'HH:mm:ss') pid=$PID ==" | Out-File -Encoding utf8 $log

$set = Bcd '/set testsigning on'
Show 'bcdedit /set testsigning on' $set

foreach ($i in 1..5) {
    Start-Sleep -Seconds 2
    $r = Bcd '/enum {current}'
    $has = $r.Text -match 'testsigning'
    $val = if ($has) { ($r.Text -split "`r?`n" | Where-Object { $_ -match 'testsigning' }) -join ';' } else { '(absent)' }
    W ("t+{0,2}s  enum{{current}} has-testsigning={1}  value='{2}'" -f ($i * 2), $has, $val)
}

$all = Bcd '/enum all'
$hits = @($all.Text -split "`r?`n" | Where-Object { $_ -match 'testsign' })
W "--- /enum all EXIT=$($all.Exit): lines mentioning testsign = $($hits.Count) ---"
foreach ($h in $hits) { W "  $h" }
W 'END'
Remove-Item $lock -Force -ErrorAction SilentlyContinue
exit 0
