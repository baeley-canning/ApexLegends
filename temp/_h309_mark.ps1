# _h309_mark.ps1 - quiet marker test: does a typed line reach the desktop foreground right now?
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h309_mark3.txt'
$b = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--profile','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','60000','--','cmd.exe','/c')
$o = @()
$o += ('start ' + (Get-Date -f 'HH:mm:ss'))
function FG {
    $sb = 'Add-Type -Name W -Namespace N -MemberDefinition ''[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int p); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);''; $h=[N.W]::GetForegroundWindow(); $p=0; [void][N.W]::GetWindowThreadProcessId($h,[ref]$p); $s=New-Object System.Text.StringBuilder 256; [void][N.W]::GetWindowText($h,$s,256); ((Get-Process -Id $p).ProcessName + " title=" + $s.ToString())'
    $t = (& $vb ($b + ('powershell -NoProfile -Command "' + $sb + '"')) 2>&1 | Out-String)
    return ($t -replace '\s+', ' ').Trim()
}
$o += ('foreground before: ' + (FG))
$k = (& $vb ($b + 'taskkill /f /im msedgewebview2.exe /im ApplicationFrameHost.exe') 2>&1 | Out-String)
$o += ('killed: ' + (($k -split "`r?`n" | Where-Object { $_ -match 'SUCCESS|not found' }) -join ' | '))
Start-Sleep -Seconds 3
(& $vb controlvm Win11-Test2 keyboardputscancode e0 5b 2>&1) | Out-Null
Start-Sleep -Milliseconds 350
(& $vb controlvm Win11-Test2 keyboardputscancode 20 a0 2>&1) | Out-Null
Start-Sleep -Milliseconds 200
(& $vb controlvm Win11-Test2 keyboardputscancode e0 db 2>&1) | Out-Null
Start-Sleep -Seconds 3
$o += ('foreground after Win+D: ' + (FG))
(& $vb controlvm Win11-Test2 keyboardputstring 'echo MARK>C:\Users\Public\h309m.txt' 2>&1) | Out-Null
Start-Sleep -Milliseconds 700
(& $vb controlvm Win11-Test2 keyboardputscancode 1c 9c 2>&1) | Out-Null
Start-Sleep -Seconds 5
$r = (& $vb ($b + 'if exist C:\Users\Public\h309m.txt (echo PRESENT) else (echo ABSENT)') 2>&1 | Out-String)
$o += ('marker: ' + ($r -replace '\s+', ' ').Trim())
Set-Content -LiteralPath $out -Value $o -Encoding ascii

# foreground window title, to see who owns focus
$t = (& $vb ($b + 'powershell -NoProfile -Command "Add-Type -Name W -Namespace N -MemberDefinition ''[DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow(); [DllImport(\"user32.dll\")] public static extern int GetWindowThreadProcessId(IntPtr h, out int p);''; $h=[N.W]::GetForegroundWindow(); $p=0; [void][N.W]::GetWindowThreadProcessId($h,[ref]$p); (Get-Process -Id $p).ProcessName"') 2>&1 | Out-String)
$o += ('foreground: ' + ($t -replace '\s+', ' ').Trim())
Set-Content -LiteralPath $out -Value $o -Encoding ascii
