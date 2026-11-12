# _h309_win.ps1 - is the Win key delivered? StartMenuExperienceHost was killed, so if Win is delivered the
# host (re)appears with a "Start" window. Then, only if that is true, use Start search to get a console.
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h309_win.txt'
$b = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--profile','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','60000','--','cmd.exe','/c')
$o = @()
$o += ('start ' + (Get-Date -f 'HH:mm:ss'))
function TL { (& $vb ($b + 'tasklist /v /fo csv /nh') 2>&1 | Out-String) }
function Count1([string]$t, [string]$pat) { return (@($t -split "`r?`n") | Where-Object { $_ -match $pat }).Count }
$t0 = TL
$o += ('baseline: start-host=' + (Count1 $t0 '"StartMenuExperienceHost') + ' consoles=' + (Count1 $t0 '^"cmd\.exe","\d+","Console","1"'))
(& $vb controlvm Win11-Test2 keyboardputscancode e0 5b 2>&1) | Out-Null
Start-Sleep -Milliseconds 350
(& $vb controlvm Win11-Test2 keyboardputscancode e0 db 2>&1) | Out-Null
Start-Sleep -Seconds 3
$t1 = TL
$host1 = Count1 $t1 '"StartMenuExperienceHost'
$o += ('after Win: start-host=' + $host1 + ' consoles=' + (Count1 $t1 '^"cmd\.exe","\d+","Console","1"'))
$o += ('start window title present: ' + ($t1 -match '"Start"'))
if ($host1 -gt 0) {
    (& $vb controlvm Win11-Test2 keyboardputstring 'cmd' 2>&1) | Out-Null
    Start-Sleep -Milliseconds 1500
    (& $vb controlvm Win11-Test2 keyboardputscancode 1c 9c 2>&1) | Out-Null
    Start-Sleep -Seconds 6
    $t2 = TL
    $o += ('after search+enter: consoles=' + (Count1 $t2 '^"cmd\.exe","\d+","Console","1"'))
}
else { $o += 'Win not delivered - Start host did not come back' }
Set-Content -LiteralPath $out -Value $o -Encoding ascii
