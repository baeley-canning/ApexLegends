# t1_transport.ps1 - read-only transport reality check. No mutation. R3: writes, never echoes.
$root = Split-Path -Parent $PSScriptRoot
$o = Join-Path $PSScriptRoot '_t1_transport.txt'
$L = New-Object System.Collections.Generic.List[string]
$L.Add('T1 ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))

$L.Add('-- services (sc query)')
foreach ($s in 'gdrv', 'gdrv2', 'gdrv3', 'GIO', 'apexdrv', 'ApexDrv', 'MsIo', 'DBUtilDrv2') {
    $q = ''
    try { $q = (('' + (& sc.exe query $s 2>&1)) -join ' ') } catch { $q = '' }
    if ($q -match 'SERVICE_NAME') {
        $st = ([regex]::Match($q, 'STATE\s+:\s+\d+\s+\w+')).Value
        $L.Add(('SVC {0,-14} -> {1}' -f $s, $st))
    } else {
        $L.Add(('SVC {0,-14} -> ABSENT' -f $s))
    }
}

$L.Add('-- loader')
$qc = ''
try { $qc = (('' + (& sc.exe qc GigabyteUpdateService 2>&1)) -join ' ') } catch { $qc = 'qc failed' }
$L.Add($qc)
$gp = @(Get-Process GigabyteUpdateService -ErrorAction SilentlyContinue)
$L.Add('GigabyteUpdateService process count = ' + $gp.Count)

$L.Add('-- driver files')
foreach ($pat in 'gdrv*', 'apex*', 'MsIo*', 'DBUtil*') {
    $f = @(Get-ChildItem 'C:\Windows\System32\drivers' -Filter $pat -ErrorAction SilentlyContinue)
    if ($f.Count -eq 0) { $L.Add(('  {0,-10} none' -f $pat)) }
    foreach ($x in $f) { $L.Add(('  {0,-16} {1,8} {2}' -f $x.Name, $x.Length, $x.LastWriteTime)) }
}

$L.Add('-- ext/ listing')
foreach ($e in @(Get-ChildItem (Join-Path $root 'ext') -File -ErrorAction SilentlyContinue)) {
    $L.Add(('  {0,-30} {1,8}' -f $e.Name, $e.Length))
}

$L.Add('-- tool refs: apexdrv vs gio/gdrv')
$pat = 'APEXDRV_WIN32_NAME|ApexDrv|apexdrv'
foreach ($d in 'ext', 'QwenKernPremium\tools') {
    $p = Join-Path $root $d
    if (-not (Test-Path $p)) { $L.Add("  $d MISSING"); continue }
    foreach ($f in @(Get-ChildItem $p -File -Filter '*.cpp' -ErrorAction SilentlyContinue)) {
        $n = @(Select-String -Path $f.FullName -Pattern $pat -AllMatches -ErrorAction SilentlyContinue).Count
        $gio = @(Select-String -Path $f.FullName -Pattern 'GIOV3|gio' -AllMatches -ErrorAction SilentlyContinue).Count
        $L.Add(('  {0,-34} apex={1,-3} gio={2}' -f $f.Name, $n, $gio))
    }
}

$L.Add('END')
($L -join "`r`n") | Out-File -FilePath $o -Encoding ascii
