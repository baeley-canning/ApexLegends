# crash_kd.ps1 - elevated body: copy the minidumps out of C:\Windows\Minidump (ACL locked)
# and run kd !analyze -v on each so we know WHICH MODULE bugchecked the box.
# Run via crash_task.ps1.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o    = Join-Path $base 'crashparse2.txt'
$dst  = Join-Path $base 'dumps'
$KD   = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
function S($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
S ("=== crash_kd {0}  admin={1} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'), $adm)
S ("boot={0} uptime={1}" -f (Get-CimInstance Win32_OperatingSystem).LastBootUpTime, ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime))

S '--- copy dumps ---'
$dumps = @()
Get-ChildItem 'C:\Windows\Minidump' -Filter '*.dmp' -Force -EA 0 | Sort-Object LastWriteTime -Descending |
  Select-Object -First 3 | ForEach-Object {
    $c = Join-Path $dst $_.Name
    try {
        Copy-Item -LiteralPath $_.FullName -Destination $c -Force -EA Stop
        S ("  copied {0}  {1} bytes  {2}" -f $_.Name, $_.Length, $_.LastWriteTime)
        $dumps += (Get-Item -LiteralPath $c)
    } catch { S ("  copy FAIL {0}: {1}" -f $_.Name, $_.Exception.Message) }
}
try {
    if (Test-Path 'C:\Windows\MEMORY.DMP') {
        S ("  MEMORY.DMP present: " + (Get-Item 'C:\Windows\MEMORY.DMP').Length)
    }
} catch { }

S ''
foreach ($d in $dumps) {
    S ('########## {0}  ({1} bytes) ##########' -f $d.Name, $d.Length)
    try {
        $out = & $KD -y 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols' -z $d.FullName `
               -c '!analyze -v; lm; q' 2>&1
        S ($out -join "`r`n")
    } catch { S ('  kd FAIL: ' + $_.Exception.Message) }
    S ''
}
S '--- end ---'
