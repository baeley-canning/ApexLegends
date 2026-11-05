# p37_gc.ps1 - host-side driver for the h268/h269+ VM probe. Every action goes through
# guestcontrol and every result is appended to p<N>_gc.txt (terminal output is unreliable here).
# Modes:
#   diag   - read-only guest diagnosis of the dead tick chain (no mutation)
#   deploy - push the h<N> probe as cur.ps1 + the chain cmd files into C:\Users\Public\p37
#   arm    - run tick.ps1 in the guest: registers p37tick/p37logon and fires one tick
#   tick   - fire one tick by hand (schtasks /run /tn p37tick)
#   pull   - pull h<N>.out + the lock + guest.log tail back
#   all    - deploy, arm, wait, pull
param([ValidateSet('diag', 'disarm', 'serve', 'deploy', 'ver', 'arm', 'tick', 'pull', 'all')][string]$Mode = 'diag', [string]$N = '268')
# -N picks the probe number: h<N>_cur.ps1 is the reviewed text, h<N>.out/lock is the guest state.
$tag   = 'h' + $N
$probe = $tag + '_cur.ps1'
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$base = Join-Path $root '_ritual'
$log  = Join-Path $base ('p' + $N + '_gc.txt')
$gd   = 'C:\Users\Public\p37'
function Say($t) { $s = (([string]$t) -replace "`0", '' -replace '[^\x20-\x7E\r\n]', ' ' -replace '\s+', ' '); if ($s.Length -gt 300) { $s = $s.Substring(0, 300) + '...[' + $s.Length + ']' }; ((Get-Date -f 'HH:mm:ss') + ' ' + $s) | Out-File -FilePath $log -Encoding utf8 -Append }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
# NB: not named GC - that is the built-in alias for Get-Content and aliases outrank functions.
function VGC([string[]]$a) { Run (@('guestcontrol', $VM, '--username', $U, '--password', $P) + $a) }
function Sh([string]$cmd) { $r = VGC @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '180000', '--', 'cmd.exe', '/c', $cmd); return [string]$r }
# copyto needs the full destination path; --target-directory alone fails with
# "Destination ... already exists and is a directory" on this VBoxManage build.
function Push([string]$src) { VGC @('copyto', $src, ($gd + '\' + (Split-Path $src -Leaf))) | Out-Null; return $LASTEXITCODE }
function MkGd { Sh ('if not exist ' + $gd + ' md ' + $gd) | Out-Null }
# After a bugcheck the guest reboots and VBoxManage fails fast with "Additions are not ready",
# turning a whole mode into noise. Guest-touching modes wait for the Additions to be up first.
function WaitGa([int]$sec = 240) {
    $deadline = (Get-Date).AddSeconds($sec)
    while ((Get-Date) -lt $deadline) {
        # this VBox build emits GuestAdditionsRunLevel=3 unquoted; older ones quote it - accept both
        if ((Run @('showvminfo', $VM, '--machinereadable')) -match 'GuestAdditionsRunLevel="?[1-9]') { return 'READY' }
        Start-Sleep -Seconds 5
    }
    return 'TIMEOUT'
}

Say ('MODE=' + $Mode)
$vs = Run @('showvminfo', $VM, '--machinereadable')
$st = ([string]($vs -split "`n" | Select-String '^VMState=')) -replace '\s+', ' '
Say ('vmstate=' + $st)
if ($st -notmatch 'running') { Say 'RESULT: VM not running - stop'; exit 1 }
if ($Mode -in 'diag', 'disarm', 'serve', 'deploy', 'ver', 'arm', 'tick', 'pull') {
    $ga = WaitGa 240
    Say ('ga=' + $ga)
    if ($ga -ne 'READY') { Say 'RESULT: guest additions never came up'; exit 1 }
}

switch ($Mode) {
    'diag' {
        MkGd
        Say ('copy rc=' + (Push (Join-Path $base 'p37_diag.ps1')))
        Say ('prepare: ' + (Sh ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + $gd + '\p37_diag.ps1 > ' + $gd + '\diag.err 2>&1 & echo rc=%ERRORLEVEL% > ' + $gd + '\rc.txt & dir /b ' + $gd + ' > ' + $gd + '\ls.txt & echo PREPARED')))
        $out = Join-Path $base 'p268_diag.txt'
        foreach ($f in 'diag.out', 'diag.err', 'rc.txt', 'ls.txt') {
            VGC @('copyfrom', ($gd + '\' + $f), (Join-Path $base ('p268_' + $f))) | Out-Null
            Say ($f + ' -> local ' + $(if (Test-Path (Join-Path $base ('p268_' + $f))) { 'ok' } else { 'missing' }))
        }
        if (Test-Path $out) { Say '--- diag ---'; Say ((Get-Content $out -EA 0) -join "`r`n") }
    }
    'disarm' {
        # stop the self-feeding chain: drop the logon trigger, the tick, and any live
        # wscript/cmd probe, then prove nothing is left running. Read-only apart from the
        # task state, so it is safe with a probe mid-flight (that probe finishes, no heir).
        Say ('dis-arm p37logon: ' + (Sh ('schtasks /change /tn p37logon /disable & echo rc=%ERRORLEVEL%')))
        Say ('dis-arm p37tick: ' + (Sh ('schtasks /change /tn p37tick /disable & echo rc=%ERRORLEVEL%')))
        Say ('killed: ' + (Sh ('taskkill /f /im wscript.exe 2>nul & taskkill /f /im powershell.exe 2>nul & echo KILLED')))
        Start-Sleep -Seconds 3
        Say ('left: ' + (Sh ('tasklist /fi "imagename eq wscript.exe" & schtasks /query /tn p37logon /fo list | findstr /i "status" & schtasks /query /tn p37tick /fo list | findstr /i "status"')))
        Say 'DISARM: expect Status=Disabled and no wscript'
    }
    'serve' {
        # once.cmd re-downloads cur.ps1 from the host on every pass, so the *served* file is
        # the real payload. Push it and prove the hash of what the guest will fetch.
        $dst = 'C:\p37vm\payload\cur.ps1'
        Copy-Item -LiteralPath (Join-Path $base $probe) -Destination ($dst + '.prev') -Force -EA 0
        Copy-Item -LiteralPath (Join-Path $base $probe) -Destination $dst -Force
        $h = (Get-FileHash $dst -Algorithm SHA256).Hash
        Say ('served ' + (Get-Item $dst).Length + 'B sha=' + $h.Substring(0, 16))
        Say ('want   ' + (Get-Item (Join-Path $base $probe)).Length + 'B sha=' + ((Get-FileHash (Join-Path $base $probe) -Algorithm SHA256).Hash.Substring(0, 16)))
        Say ('SERVE: ' + $(if ($h -eq (Get-FileHash (Join-Path $base $probe) -Algorithm SHA256).Hash) { 'MATCH' } else { 'MISMATCH' }))
        Say ('server: ' + (Sh ('powershell -NoProfile -c "try { (New-Object Net.WebClient).DownloadString(''http://10.0.2.2:8080/cur.ps1'').Length } catch { ''DEAD'' }"')))
    }
    'deploy' {
        MkGd
        # a reboot wipes the chain but leaves no trace of what it took: clear every stale
        # target first so a re-run is deterministic (copyto also refuses an existing dest).
        Say ('clean: ' + (Sh ('del /q ' + $gd + '\cur.ps1 ' + $gd + '\' + $probe + ' ' + $gd + '\run.cmd ' + $gd + '\once.cmd ' + $gd + '\tick.ps1 2>nul & echo CLEANED')))
        Say ('cur.ps1 push rc=' + (Push (Join-Path $base $probe)))
        # NB: `if exist X del X && ren ...` parses as `if exist X (del X && ren ...)`, so when
        # cur.ps1 is already gone the rename never runs. Keep ren as its own statement.
        Say ('rename: ' + (Sh ('ren ' + $gd + '\' + $probe + ' cur.ps1 & if exist ' + $gd + '\cur.ps1 (echo RENAMED) else (echo RENAME_FAIL)')))
        foreach ($f in 'run.cmd', 'once.cmd', 'tick.ps1') {
            Say ($f + ' rc=' + (Push (Join-Path 'C:\p37vm\payload' $f)))
        }
        $have = Sh ('for %f in (tick.ps1 run.cmd once.cmd cur.ps1) do @if exist ' + $gd + '\%f (echo yes %f) else (echo NO %f)')
        Say ('verify: ' + ($have -replace '\s+', ' '))
        Say ('cur.ps1 size: ' + (Sh ('for %f in (' + $gd + '\cur.ps1) do @echo %~zf bytes')))
        Say ($probe + ' left: ' + (Sh ('if exist ' + $gd + '\' + $probe + ' (echo YES) else (echo NO)')))
        Say ('DEPLOY: ' + $(if ($have -match 'yes cur.ps1' -and $have -match 'yes once.cmd' -and $have -match 'yes run.cmd' -and $have -match 'yes tick.ps1' -and $have -notmatch 'NO ') { 'OK' } else { 'FAIL' }))
        Say ('ls: ' + (Sh ('dir /b ' + $gd)))
    }
    'ver' {
        # deployed-file read-back: the guest copy must be byte-identical to the reviewed text
        $got = Join-Path $base ('p' + $N + '_deployed_cur.ps1')
        Remove-Item -LiteralPath $got -Force -EA 0
        Say ('copyfrom cur.ps1: ' + (VGC @('copyfrom', ($gd + '\cur.ps1'), $got)))
        $src = Join-Path $base $probe
        if ((Test-Path $got) -and (Test-Path $src)) {
            $a = (Get-FileHash $got -Algorithm SHA256).Hash; $b = (Get-FileHash $src -Algorithm SHA256).Hash
            Say ('deployed ' + (Get-Item $got).Length + 'B sha=' + $a.Substring(0, 16))
            Say ('reviewed ' + (Get-Item $src).Length + 'B sha=' + $b.Substring(0, 16))
            Say ('VER: ' + $(if ($a -eq $b) { 'MATCH' } else { 'MISMATCH' }))
        } else { Say 'VER: FAIL copyfrom' }
    }
    'arm' {
        Say ('arm: ' + (Sh ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + $gd + '\tick.ps1')))
        Say ('tasks: ' + (Sh ('schtasks /query /tn p37tick /fo list | findstr /i "TaskName Status Next Last"')))
    }
    'tick' {
        $t = Sh ('schtasks /run /tn p37tick & echo TICK_RC=%ERRORLEVEL%')
        Say ('tick: ' + $t)
        Say ('TICK: ' + $(if ($t -match 'TICK_RC=0') { 'OK' } else { 'FAIL' }))
    }
    'pull' {
        $out = Join-Path $base ('p' + $N + '_guest_' + $tag + '.txt')
        Say ('pull ' + $tag + '.out: ' + (VGC @('copyfrom', ($gd + '\' + $tag + '.out'), $out)))
        if (Test-Path $out) { Say ($tag + '.out ' + (Get-Item $out).Length + 'B - read it next') } else { Say ('(no ' + $tag + '.out)') }
        $pv = Join-Path $base ('p' + $N + '_guest_' + $tag + '_prev.txt')
        Say ('pull ' + $tag + '.prev.out: ' + (VGC @('copyfrom', ($gd + '\' + $tag + '.prev.out'), $pv)))
        if (Test-Path $pv) { Say ($tag + '.prev.out ' + (Get-Item $pv).Length + 'B - crashed-run tail') }
        # unique crash tails: fetch any hist file not already on the host
        $hist = Join-Path $base ('p' + $N + '_hist')
        if (-not (Test-Path $hist)) { New-Item -ItemType Directory -Path $hist -Force | Out-Null }
        $names = (Sh ('cmd /c dir /b ' + $gd + '\' + $tag + '.hist.*.out 2>nul')) -split "`r?`n" | Where-Object { $_ -match '\.out$' }
        Say ('hist count=' + @($names).Count)
        foreach ($n in $names) {
            $leaf = $n.Trim()
            if (Test-Path (Join-Path $hist $leaf)) { continue }
            Say ('hist ' + $leaf + ': ' + (VGC @('copyfrom', ($gd + '\' + $leaf), (Join-Path $hist $leaf))))
        }
        Say ('lock: ' + (Sh ('type ' + $gd + '\' + $tag + '.lock')))
        # bugcheck minidumps staged under the same dir by the WinRE pass
        $dd = Join-Path $base ('p' + $N + '_dumps')
        if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
        $dn = (Sh ('cmd /c dir /b ' + $gd + '\dumps\*.dmp 2>nul')) -split "`r?`n" | Where-Object { $_ -match '\.dmp$' }
        Say ('dump count=' + @($dn).Count)
        foreach ($n in $dn) {
            $leaf = $n.Trim()
            if (Test-Path (Join-Path $dd $leaf)) { continue }
            Say ('dump ' + $leaf + ': ' + (VGC @('copyfrom', ($gd + '\dumps\' + $leaf), (Join-Path $dd $leaf))))
        }
        Say ('guest.log tail: ' + (Sh ('powershell -NoProfile -c "Get-Content ' + $gd + '\guest.log -Tail 20 -EA 0"')))
    }
    'all' {
        Say 'disarm+serve+deploy+arm+pull'
        & $PSCommandPath -Mode disarm -N $N
        & $PSCommandPath -Mode serve -N $N
        & $PSCommandPath -Mode deploy -N $N
        Start-Sleep -Seconds 1
        & $PSCommandPath -Mode arm -N $N
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 15
            $h = (Get-Content ('C:\p37vm\guest-' + $tag + '.log') -Tail 3 -EA 0) -join ' '
            Say ('poll ' + $i + ': ' + ($h -replace '\s+', ' '))
            if ($h -match 'VERDICT:|RESULT: (FAIL|PENDING)') { break }
        }
        & $PSCommandPath -Mode pull -N $N
    }
}
Say 'END'
