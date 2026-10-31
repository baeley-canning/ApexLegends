# diag_eac.ps1 -- what state is the machine in after EAC rejected the session?
# Everything goes to diag_eac.txt; the console is unreliable here.
$out = Join-Path $PSScriptRoot 'diag_eac.txt'
$lines = New-Object System.Collections.Generic.List[string]
function L($s) { $lines.Add($s) }

L '=== boot config (bcdedit)'
$bcd = (bcdedit) 2>&1
foreach ($k in 'testsigning', 'nointegritychecks', 'debug ', 'hypervisorlaunchtype',
               'SecureBoot', 'vsmlaunchtype', 'isolatedcontext') {
    $hit = $bcd | Select-String -SimpleMatch $k
    if ($hit) { foreach ($h in $hit) { L ("  " + $h.Line.Trim()) } }
    else { L ("  ($k) <absent>") }
}

L ''
L '=== os'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
L ("  product   = " + $cv.ProductName)
L ("  version   = " + $cv.DisplayVersion + " build " + $cv.CurrentBuild + "." + $cv.UBR)
L ("  edition   = " + $cv.EditionID)
L ("  installed = " + $cv.InstallDate)
L ("  uptime    = " + ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime))

L ''
L '=== secure boot / HVCI / VBS'
$sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
L ("  UEFISecureBootEnabled = " + $sb)
try {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
    L ("  VBS status            = " + $dg.VirtualizationBasedSecurityStatus + "  (0=off 1=configured 2=running)")
    L ("  services running      = " + ($dg.SecurityServicesRunning -join ',') + "  (1=CredGuard 2=HVCI 3=both)")
    L ("  services configured   = " + ($dg.SecurityServicesConfigured -join ','))
} catch { L ("  DeviceGuard query failed: " + $_.Exception.Message) }
$hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue).Enabled
L ("  HVCI reg Enabled      = " + $hvci)

L ''
L '=== driver / service'
L ("  apexr.sys on disk     = " + (Test-Path "$env:SystemRoot\System32\drivers\apexr.sys"))
L ("  device \\\\.\\apexr      = " + (Test-Path '\\.\apexr'))
$svc = (sc.exe query apexr) 2>&1
foreach ($s in $svc) { if ($s -match 'STATE|EXIT_CODE|TYPE') { L ("  " + $s.Trim()) } }

L ''
L '=== potentially blocklisted / byovd drivers present'
$names = 'AsIO', 'AsIO2', 'AsIO3', 'AsUpIO', 'iqvw64e', 'gdrv', 'gdrv2', 'WinIO',
         'EneIo', 'EneTechIo', 'inpoutx64', 'msio', 'msio64', 'RTCore64', 'LgCoreTemp',
         'cpuz', 'NiVi', 'nvflash', 'speedfan', 'ThrottleStop', 'WinRing0'
$found = @()
foreach ($n in $names) {
    $f = Get-ChildItem "$env:SystemRoot\System32\drivers" -Filter "$n*" -ErrorAction SilentlyContinue
    foreach ($x in $f) { $found += ($x.Name + "  " + $x.Length + "  " + $x.LastWriteTime) }
}
if ($found) { foreach ($f in $found) { L ("  " + $f) } } else { L '  none of the usual names' }

L ''
L '=== protocol / filter drivers mentioning apex or asus'
Get-ChildItem "$env:SystemRoot\System32\drivers" -Filter '*.sys' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'apex|asio|asus|armoury' } |
    ForEach-Object { L ("  " + $_.Name + "  " + $_.Length) }

L ''
L '=== EA anti-cheat logs (recent)'
$roots = @("$env:LOCALAPPDATA\Temp", "$env:LOCALAPPDATA\EA", "$env:ProgramData\EA Anti-Cheat",
           "$env:ProgramData\Electronic Arts", "$env:APPDATA\EA")
foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    $f = Get-ChildItem $r -Recurse -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match 'EAC|Javelin|anti' -and $_.LastWriteTime -gt (Get-Date).AddHours(-6) } |
         Sort-Object LastWriteTime -Descending | Select-Object -First 8
    foreach ($x in $f) { L ("  " + $x.LastWriteTime.ToString('HH:mm:ss') + "  " + $x.FullName) }
}

L ''
L '=== game / launcher processes now'
Get-Process | Where-Object { $_.Name -match 'apex|EA|Javelin|Easy' } | ForEach-Object {
    $st = ''
    try { $st = $_.StartTime.ToString('HH:mm:ss') } catch { $st = '(no access)' }
    L ("  " + $_.Name + " pid=" + $_.Id + " started=" + $st)
}

Set-Content -LiteralPath $out -Value ($lines -join "`r`n") -Encoding UTF8
Write-Host ("wrote " + $out)
