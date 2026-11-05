# _resume_state.ps1 -- READ-ONLY post-reboot state re-read (R3).  No mutation.
$T = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$o = Join-Path $T '_resume_state.txt'
$m = @()
$m += 'now ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss')
$m += 'lastboot ' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$m += '=== driver services ==='
foreach ($s in 'gdrv3', 'apexdrv') {
    $q = (& sc.exe query $s 2>&1) -join ' ~~ '
    $m += ("{0}: {1}" -f $s, $q)
}
$m += '=== blocklist / bcd ==='
$m += ((& reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Config' 2>&1) -join ' ~~ ')
$m += ((& bcdedit /enum '{current}' 2>&1 | Select-String 'hypervisorlaunchtype|testsigning|nointegritychecks') -join ' ~~ ')
$m += '=== processes ==='
$m += ((Get-Process r5apex, r5apex_dx12, EADesktop, EAAntiCheat.GameServiceLauncher, python -EA SilentlyContinue |
    Select-Object Name, Id, StartTime) | Format-Table -AutoSize | Out-String -Width 160)
$m += '=== run artifacts ==='
foreach ($f in '_p107g_out.txt', '_p107g_task.log', '_p107g_launch.txt', '_p96_refresh.txt') {
    $p = Join-Path $T $f
    $m += ("{0} exists={1} len={2}" -f $f, (Test-Path -LiteralPath $p),
        $(if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p).Length } else { 0 }))
}
$m += '=== p96 prog tail ==='
$m += (@(Get-Content -LiteralPath (Join-Path $T '_p96_prog.txt') -Tail 6 -EA SilentlyContinue) -join "`r`n")
$m += '=== p107g task ==='
$m += ((@(Get-ScheduledTask -TaskName 'QwenKern_p107g' -EA SilentlyContinue) | ForEach-Object { $_.State }) -join ',')
$m += '=== c:\p37vm ==='
$m += ('exists=' + (Test-Path 'C:\p37vm'))
($m -join "`r`n") | Set-Content -LiteralPath $o -Encoding UTF8
Write-Host ('wrote ' + $o)
