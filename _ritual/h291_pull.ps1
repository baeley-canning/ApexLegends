# h291_pull.ps1 - probe #291 (variable: evidence SOURCE - the minidump on disk, not the event log)
# h290's park report gave the 0x50 signature from BugCheck 1001:
#   Arg1=0xfffff60385f5e000 (referenced address, unmapped), Arg2=0 (read),
#   Arg3=0xfffff80219033bc9 (faulting instruction pointer), Arg4=2.
# The 1001 params name the address but not the module. The minidump carries the loaded-module
# list, so `lm` resolves Arg3 -> module+offset with no symbols at all. This probe:
#   1. lists C:\Windows\Minidump over guestcontrol (read-only),
#   2. copies the newest dump to temp\,
#   3. runs kd -z against it and prints the module range that contains Arg3.
# Read-only on the guest: dir + copyfrom. No driver start/stop, no service change, no boot
# config, no reboot. Re-runnable; output is a new file each time (R5): _ritual\h291_pull.txt.
$ErrorActionPreference = 'Continue'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out = Join-Path $d 'h291_pull.txt'
$kd  = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$RIP = '0xfffff80219033bc9'
function W($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss.fff'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Set-Content -LiteralPath $out -Value ("{0} === h291 pull: resolve $RIP from the minidump (variable: evidence source) ===" -f (Get-Date -f 'HH:mm:ss.fff'))
function G([string[]]$a) { $o = (& $v guestcontrol $VM --username vboxuser --password vboxuser @a 2>&1) -join ' / '; return @{ rc = $LASTEXITCODE; o = $o } }

# --- 0. pre-state: is the guest still up and is the channel usable at all (R3) ---
$st = (& $v showvminfo $VM --machinereadable 2>&1) -join "`n"
$vmState = ([regex]::Match($st, 'VMState="([^"]+)"')).Groups[1].Value
$ga      = ([regex]::Match($st, 'GuestAdditionsRunLevel="([^"]*)"')).Groups[1].Value
W ("pre vm: VMState=$vmState GuestAdditionsRunLevel=$ga")
if ($vmState -ne 'running') { W 'RESULT: FAIL - guest not running, nothing pulled (variable: evidence source)'; W 'VERDICT: no evidence read; the guest must be up for guestcontrol'; exit 1 }

# --- 1. list the dumps (guest-side, read-only) ---
$r = G @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--timeout', '60000', '--wait-stdout', '--wait-stderr', '--', 'cmd', '/c dir /o-d C:\Windows\Minidump\*.dmp > C:\Users\Public\h291_dumps.txt 2>&1')
W ("dir rc=$($r.rc)")
$r2 = G @('copyfrom', 'C:\Users\Public\h291_dumps.txt', (Join-Path $tmp 'h291_dumps.txt'))
W ("copyfrom list rc=$($r2.rc) exists=$(Test-Path -LiteralPath (Join-Path $tmp 'h291_dumps.txt'))")
$listFile = Join-Path $tmp 'h291_dumps.txt'
if (-not (Test-Path -LiteralPath $listFile)) { W 'RESULT: FAIL - could not read the guest dump listing (variable: evidence source)'; W 'VERDICT: guestcontrol copyfrom failed; no dump analysed'; exit 1 }
$lines = @(Get-Content -LiteralPath $listFile -EA 0)
foreach ($l in $lines) { if ($l.Trim()) { W ('  dir ' + $l.Trim()) } }
$dumps = @($lines | Where-Object { $_ -match '(\d\d/\d\d/\d{4})\s+(\d\d:\d\d)\s+([\d,]+)\s+(\S+\.dmp)' } | ForEach-Object {
        $null = $_ -match '(\d\d/\d\d/\d{4})\s+(\d\d:\d\d)\s+([\d,]+)\s+(\S+\.dmp)'
        [pscustomobject]@{ When = "$($Matches[1]) $($Matches[2])"; Bytes = $Matches[3]; Name = $Matches[4] } })
W ('dumps listed=' + $dumps.Count)
if ($dumps.Count -lt 1) { W 'RESULT: FAIL - no minidump parsed from the listing (variable: evidence source)'; W 'VERDICT: nothing to analyse'; exit 1 }
$newest = $dumps[0]
W ('newest: ' + $newest.Name + ' ' + $newest.Bytes + 'b ' + $newest.When)

# --- 2. pull that one dump (read-only copy out) ---
$local = Join-Path $tmp ('h291_' + $newest.Name)
if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
$r3 = G @('copyfrom', ('C:\Windows\Minidump\' + $newest.Name), $local)
$sz = 0
if (Test-Path -LiteralPath $local) { $sz = (Get-Item -LiteralPath $local).Length }
W ("copyfrom dump rc=$($r3.rc) bytes=$sz path=$local")
if ($sz -lt 10000) { W 'RESULT: FAIL - dump copy truncated or missing (variable: evidence source)'; W ("VERDICT: copyfrom said rc=$($r3.rc); nothing analysable on the host"); exit 1 }

# --- 3. resolve Arg3 with kd, from the dump's own module list (no symbols needed for lm) ---
$klog = Join-Path $tmp 'h291_kd.txt'
if (Test-Path -LiteralPath $klog) { Remove-Item -LiteralPath $klog -Force }
W '--- kd (lm; .bugcheck; q), 300 s budget ---'
$p = Start-Process -FilePath $kd -ArgumentList ('-z "' + $local + '" -logo "' + $klog + '" -c ".bugcheck; lm; q"') -NoNewWindow -Wait -PassThru -EA 0
W ("kd finished pid=$($p.Id) logo=$(Test-Path -LiteralPath $klog)")
if (-not (Test-Path -LiteralPath $klog)) { W 'RESULT: FAIL - kd produced no log (variable: evidence source)'; W 'VERDICT: no module resolution'; exit 1 }
$k = @(Get-Content -LiteralPath $klog -EA 0)
W ('kd log lines=' + $k.Count)
foreach ($l in $k) { if ($l -match 'Bugcheck code|Bugcheck 0x|Arg[1-4]|Probably caused|FAULTING') { W ('  k ' + $l.TrimEnd()) } }
$hit = $null
foreach ($l in $k) {
    if ($l -match '^\s*([0-9a-f`]{8,17})\s+([0-9a-f`]{8,17})\s+(\S+)\s+(.*)$') {
        $b = $Matches[1] -replace '`', ''; $e = $Matches[2] -replace '`', ''
        if ($b -match '^[0-9a-f]+$' -and $e -match '^[0-9a-f]+$' -and $b.Length -ge 8) {
            $bv = [Convert]::ToUInt64($b.PadLeft(16, '0'), 16); $ev = [Convert]::ToUInt64($e.PadLeft(16, '0'), 16)
            $rip = [Convert]::ToUInt64(($RIP -replace '0x', '').PadLeft(16, '0'), 16)
            if ($rip -ge $bv -and $rip -le $ev) { $hit = ('base=' + $Matches[1] + ' end=' + $Matches[2] + ' module=' + $Matches[3] + ' ' + $Matches[4]); break }
        }
    }
}
foreach ($l in $k) { if ($l -match $RIP.Substring(2)) { W ('  x ' + $l.TrimEnd()) } }
if ($hit) { W ('MODULE CONTAINING RIP: ' + $hit) } else { W 'MODULE CONTAINING RIP: not found in lm output' }
W '--- kd log: first 30 lines ---'
foreach ($l in @($k | Select-Object -First 30)) { W ('  r ' + $l.TrimEnd()) }
if ($hit) {
    W 'RESULT: PASS - crash RIP resolved to a module from the dump module list (variable: evidence source)'
    W 'VERDICT: the module in MODULE CONTAINING RIP owns the faulting instruction; that is the crash site'
} else {
    W 'RESULT: PARTIAL - dump pulled and kd ran, but no lm range contains the RIP (variable: evidence source)'
    W 'VERDICT: inspect the kd log lines above before naming a driver'
}
