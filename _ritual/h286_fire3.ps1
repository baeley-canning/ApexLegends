# h286_fire3.ps1 - fire the tick once more, properly detached, and poll the log for growth.
# v2 (h286_fire2) died at the channel probe at 15:01 while GA was 0 (guest in WinRE); the
# Start-Process relaunch broke because the path with spaces was split across argv. Here the
# whole -File argument is a single quoted string. Fire is manual per HANDOFF ("one-shot").
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h286_fire3.txt'
$log = 'C:\p37vm\guest-h286.log'
$so  = "$env:TEMP\h286_3o.txt"; $se = "$env:TEMP\h286_3e.txt"
Remove-Item -LiteralPath $out -Force -EA 0
Remove-Item -LiteralPath $so,$se -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function Gcx([string]$label, [string[]]$argv, [int]$cap) {
    $p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    if ($p.WaitForExit($cap)) {
        $t = (((Get-Content $so -Raw -EA 0) + (Get-Content $se -Raw -EA 0)) -replace '\s+', ' ').Trim()
        W ($label + ' rc=' + $p.ExitCode + ' out=[' + $t + ']')
        return $p.ExitCode
    }
    try { $p.Kill() } catch { }
    W ($label + ' TIMEOUT ' + $cap + ' ms (killed)')
    return 1
}
$before = (Get-Item $log -EA 0).Length
W ('=== h286 fire3: gc fire + log growth poll === log_before=' + $before)
$probe = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','20000','--','cmd.exe','/c','whoami & wmic os get lastbootuptime')
if ((Gcx 'probe' $probe 45000) -ne 0) { W 'RESULT: FIRE3 FAILED - gc channel dead'; W 'VERDICT: tick not fired'; exit 1 }
$boot = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','20000','--','cmd.exe','/c','powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime"')
Gcx 'lastboot' $boot 45000 | Out-Null
$fire = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','30000','--','cmd.exe','/c','schtasks /run /tn p37tick')
if ((Gcx 'fire' $fire 45000) -ne 0) { W 'RESULT: FIRE3 FAILED - trigger refused (access denied?)'; W 'VERDICT: tick not fired'; exit 1 }
W '  fired; polling log for growth'
$new = ''
for ($i = 1; $i -le 16; $i++) {
    Start-Sleep -Seconds 15
    $len = (Get-Item $log -EA 0).Length
    $tail = (Get-Content $log -Tail 3 -EA 0) -join ' | '
    W ("t+" + (15*$i) + "s len=" + $len + " tail: " + $tail)
    $txt = Get-Content $log -Raw -EA 0
    if ($txt -match 'VERDICT:') { $new = 'VERDICT'; break }
}
$txt = Get-Content $log -Raw -EA 0
$v = ($txt -split "`n" | Select-String '^(RESULT|VERDICT|targetinfo|delivery|modules):').Line
W '--- verdict lines in log ---'
$v | Select-Object -Last 8 | ForEach-Object { W ('  ' + $_) }
if ($v) { W 'RESULT: h286 verdict present in log (see lines above)' } else { W 'RESULT: h286 NO verdict line yet' }
W 'VERDICT: see RESULT line above'
