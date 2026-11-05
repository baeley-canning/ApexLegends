# p43c - read-only post-Repair game state.  No elevation, no mutation.
# Run AFTER the user has done EA Repair and relaunched to the lobby.
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43c_game.txt'
$L = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date).ToString('s'))
$g = Get-Process -Name 'r5apex_dx12' -ErrorAction SilentlyContinue
if (-not $g) { $L.Add('GAME absent') } else {
    foreach ($p in $g) {
        $L.Add("GAME pid=$($p.Id) ws=$([int]($p.WorkingSet64/1MB))MB cpu=$([math]::Round($p.CPU,1))s start=$($p.StartTime.ToString('s')) responding=$($p.Responding) title='$($p.MainWindowTitle)'")
    }
}
foreach ($n in 'EADesktop', 'EABackgroundService', 'EAAntiCheat.GameService', 'EAAntiCheatService') {
    $p = Get-Process -Name $n -ErrorAction SilentlyContinue
    $L.Add("proc $n = " + $(if ($p) { 'alive' } else { 'absent' }))
}
foreach ($s in 'EAAntiCheatService', 'eaanticheat', 'gdrv3') {
    $q = sc.exe query $s 2>&1 | Select-String 'STATE'
    $L.Add("svc $s : " + ($q -join ' ').Trim())
}
$L.Add('--- last 6 WHEA 18/19/47 (newest first) ---')
$ev = wevtutil qe System '/q:*[System[(EventID=18 or EventID=19 or EventID=47)]]' /c:6 /rd:true /f:text 2>&1 |
      Select-String 'Event ID|Date|Cache|APIC'
if ($ev) { foreach ($e in $ev) { $L.Add('  ' + $e.Line.Trim()) } } else { $L.Add('  none') }
$L.Add('--- capacity / dumps ---')
$L.Add('free C: = ' + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + ' GB')
$L.Add('minidumps (elevated list needed for detail); newest 3 by name: ' + ((Get-ChildItem 'C:\Windows\Minidump' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 -ExpandProperty Name) -join ', '))
$L.Add('--- last logged verdict ---')
$L.Add((Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt' -Tail 3 -ErrorAction SilentlyContinue) -join ' | ')
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
Get-Content -LiteralPath $o
