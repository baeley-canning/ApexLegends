# build\_find_game_path.ps1  (read-only)
$out = 'C:\ProgramData\_qwen_findpath.txt'
$l = @()

$l += '--- Win32_Process ---'
$wp = Get-CimInstance Win32_Process -Filter "ProcessId=11996" -ErrorAction SilentlyContinue
if ($wp) { $l += ("name={0}`nexec={1}`ncmd={2}" -f $wp.Name, $wp.ExecutablePath, $wp.CommandLine) }
else { $l += '<no wmi row>' }

$l += '--- registry InstallDir candidates ---'
foreach ($k in @(
    'HKLM:\SOFTWARE\WOW6432Node\Respawn\Apex',
    'HKLM:\SOFTWARE\Respawn\Apex',
    'HKCU:\SOFTWARE\Respawn\Apex',
    'HKLM:\SOFTWARE\WOW6432Node\Electronic Arts\EA Games\Apex',
    'HKLM:\SOFTWARE\Electronic Arts\EA Games\Apex')) {
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    if ($p) { $l += ("{0} -> InstallDir={1} Setting.Install Dir={2}" -f $k, $p.InstallDir, $p.'Install Dir') }
}

$l += '--- cheese/known dirs ---'
foreach ($d in @('C:\Program Files\EA Games', 'D:\EA Games', 'E:\EA Games',
                 'C:\Program Files (x86)\Origin Games', 'C:\Program Files\EA Games\Apex')) {
    if (Test-Path $d) { $l += "exists: $d"; Get-ChildItem $d -Directory -ErrorAction SilentlyContinue | ForEach-Object { $l += "  " + $_.FullName } }
}

$l += '--- targeted file search (shallow) ---'
$roots = @('C:\Program Files\EA Games', 'D:\', 'E:\', 'C:\Games', 'C:\Program Files (x86)')
foreach ($r in $roots) {
    if (Test-Path $r) {
        $hit = Get-ChildItem $r -Filter 'r5apex_dx12.exe' -Recurse -Depth 4 -File -ErrorAction SilentlyContinue | Select-Object -First 3
        foreach ($h in $hit) { $l += $h.FullName }
    }
}

$l | Out-File -FilePath $out -Encoding utf8
