# h133 - READ-ONLY minidump inventory (System32\Minidump ACL hides it from unelevated shells).
# Lists dumps (name/time/size) + last WHEA-18 events (time/APIC/type) so each dump can be
# mapped to a crash hour. Self-elevates once. Output: temp\_h133_dumps.txt. No mutations.
$ErrorActionPreference = 'SilentlyContinue'
$tmp = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp'
$out = Join-Path $tmp '_h133_dumps.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    Get-Content -LiteralPath $out
    exit 0
}
$m = @()
$m += ('h133 ' + (Get-Date -f 'HH:mm:ss'))
$m += '=== dumps ==='
$d = @(Get-ChildItem 'C:\Windows\Minidump' -EA SilentlyContinue | Sort-Object LastWriteTime)
foreach ($f in $d) { $m += ($f.LastWriteTime.ToString('dd/HH:mm:ss') + '  ' + [int]($f.Length/1KB) + 'KB  ' + $f.Name) }
$m += ('count=' + $d.Count)
$m += ('memorydmp=' + (Test-Path 'C:\Windows\MEMORY.DMP'))
$m += '=== last WHEA-18 ==='
$w = @(Get-WinEvent -FilterHashtable @{LogName='System';Id=18;StartTime=(Get-Date).Date} -EA SilentlyContinue | Select-Object -First 6)
foreach ($e in $w) { $m += ($e.TimeCreated.ToString('HH:mm:ss') + '  ' + (($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(140, $e.Message.Length)))) }
$m += '=== last 1001 today ==='
$b = @(Get-WinEvent -FilterHashtable @{LogName='System';Id=1001;StartTime=(Get-Date).Date} -EA SilentlyContinue | Select-Object -First 3)
foreach ($e in $b) { $m += ($e.TimeCreated.ToString('HH:mm:ss') + '  ' + (($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(200, $e.Message.Length)))) }
$m += 'VERDICT DUMP_INVENTORY_DONE (read-only)'
($m -join "`r`n") | Set-Content -LiteralPath $out -Encoding UTF8
Get-Content -LiteralPath $out
