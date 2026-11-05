# h134 - deep MCE decode of the FRESHEST dump only (110526-14640-01.dmp, 14:22:57).
# crash_kd.ps1 would overwrite crashparse2.txt -> new number, own output (R5).
# Read-only: copies one dump out of the ACL-locked Minidump dir, runs kd !analyze -v,
# extracts the WHEA record address (Arg2) from that output, then !errrec on it for the
# bank/MCi_STATUS/ProcessorId decode. Also dumps full WHEA-18 event texts (APIC field).
# Output: temp\_h134_mce.txt
$ErrorActionPreference = 'SilentlyContinue'
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp  = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp'
$out  = Join-Path $tmp '_h134_mce.txt'
$dst  = Join-Path $base 'dumps'
$KD   = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
function S($t) { $t | Out-File -FilePath $out -Encoding ascii -Append }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    Get-Content -LiteralPath $out
    exit 0
}
if (Test-Path $out) { Remove-Item $out -Force }
S ('=== h134 ' + (Get-Date -f 'HH:mm:ss') + ' adm=1 ===')
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
$src = Join-Path 'C:\Windows\Minidump' '110526-14640-01.dmp'
$c   = Join-Path $dst '110526-14640-01.dmp'
Copy-Item -LiteralPath $src -Destination $c -Force
S ('copied ' + (Get-Item $c).Length + ' bytes')
S '=== EVENT WHEA-18 FULL TEXT (APIC lives here) ==='
$ev = @(Get-WinEvent -FilterHashtable @{LogName='System';Id=18;StartTime=(Get-Date).Date} -EA SilentlyContinue | Select-Object -First 6)
foreach ($e in $ev) { S ('-- ' + $e.TimeCreated.ToString('HH:mm:ss')); S ($e.Message -replace "`r?`n", ' | ') }
S '=== KD ANALYZE ==='
$o1 = (& $KD -y 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols' -z $c -c '!analyze -v; q' 2>&1) -join "`r`n"
S $o1
$rec = $null
if ($o1 -match 'Arg2:\s+([0-9a-f]{8}`[0-9a-f]{8})') { $rec = $Matches[1].Replace('`', '') }
S ('RECORD=' + $rec)
if ($rec) {
    S '=== ERR REC DECODE ==='
    $o2 = (& $KD -y 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols' -z $c -c ('!errrec 0x' + $rec + '; q') 2>&1) -join "`r`n"
    S $o2
}
S '=== EXTRACT ==='
foreach ($ln in (($o1 + "`r`n" + $o2) -split "`r?`n")) {
    if ($ln -match 'Processor ID|APIC|Bank|MCi_STATUS|MCACOD|MISC|VALID|VALID|UNCORRECT|addr') { S ('  > ' + $ln.Trim()) }
}
S 'VERDICT MCE_DECODE_DONE'
Get-Content -LiteralPath $out
