# p108_dumps.ps1 -- stop Windows deleting the crash dumps, because there is
# nothing left to analyze.
#
# Evidence: three bugchecks today (13:15:26, 13:27:31, 13:59:01), all
# 0x124 with a WHEA error record (0xfe000000 / 0x80113a), and the matching
# WHEA-Logger id=18 records all say the same thing:
#   "Processor Core ... Machine Check Exception ... Cache Hierarchy Error ...
#    Processor APIC ID: 48" (13:15 and 13:27) and APIC ID 25 (13:59).
# C:\Windows\Minidump is EMPTY and C:\Windows\MEMORY.DMP is absent even though
# WER names the dmp file it "saved" (110526-10625-01.dmp etc.). CrashDumpEnabled=3
# (small dump) but AlwaysKeepMemoryDump is unset, so the automatic cleanup pass
# removes them. Without a dump every crash stays a guess.
#
# One variable: HKLM\SYSTEM\CurrentControlSet\Control\CrashControl
# \AlwaysKeepMemoryDump  unset -> 1.  Nothing else is touched.
#
# R4: the prior value is recorded to temp\_p108_restore.txt before the write and
# `-Restore` puts it back (delete = prior absent).  No boot effect, so host-only
# is fine (R1 does not cover CrashControl; nothing loads or unloads).
#
# -Inner is unused, kept so this matches the other pNN wrappers.
param([switch]$Restore)

$root = Split-Path -Parent $PSScriptRoot
$pre  = Join-Path $root 'temp\_p108_pre.txt'
$bak  = Join-Path $root 'temp\_p108_restore.txt'
$key  = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Restore) { $a += ' -Restore' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    exit 0
}

$cur = Get-ItemProperty -LiteralPath $key
$had = $null -ne $cur.PSObject.Properties['AlwaysKeepMemoryDump']
$old = if ($had) { $cur.AlwaysKeepMemoryDump } else { '<absent>' }

$msg = @()
$msg += ('pre ' + (Get-Date -f 'HH:mm:ss') + '  boot ' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
$msg += ('mode=' + $(if ($Restore) { 'RESTORE' } else { 'SET' }))
$msg += ('CrashDumpEnabled=' + $cur.CrashDumpEnabled + ' AutoReboot=' + $cur.AutoReboot + ' Overwrite=' + $cur.Overwrite)
$msg += ('AlwaysKeepMemoryDump before=' + $old + ' (present=' + $had + ')')
$msg += ('minidumps=' + (@(Get-ChildItem 'C:\Windows\Minidump' -EA SilentlyContinue).Count) + ' memdmp=' + (Test-Path -LiteralPath 'C:\Windows\MEMORY.DMP'))
$msg += ('bugchecks today=' + (@(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=(Get-Date).Date} -EA SilentlyContinue).Count))
($msg -join "`r`n") | Set-Content -LiteralPath $pre -Encoding UTF8

# R4 restore leg, written before the mutation so it survives a crash mid-way.
@(
    ('prior_present=' + $had)
    ('prior_value=' + $old)
    ('restore_cmd=Remove-ItemProperty -LiteralPath "' + $key + '" -Name AlwaysKeepMemoryDump -EA SilentlyContinue   # only if prior_present=False')
    ('restore_cmd2=Set-ItemProperty -LiteralPath "' + $key + '" -Name AlwaysKeepMemoryDump -Value ' + $old + ' -Type DWord   # only if prior_present=True')
) | Set-Content -LiteralPath $bak -Encoding UTF8

$err = ''
try {
    if ($Restore) {
        if ($had) { Set-ItemProperty -LiteralPath $key -Name AlwaysKeepMemoryDump -Value ([int]$old) -Type DWord }
        else      { Remove-ItemProperty -LiteralPath $key -Name AlwaysKeepMemoryDump -EA SilentlyContinue }
    } else {
        Set-ItemProperty -LiteralPath $key -Name AlwaysKeepMemoryDump -Value 1 -Type DWord
    }
} catch { $err = $_.Exception.Message }

$now = Get-ItemProperty -LiteralPath $key
$val = $now.AlwaysKeepMemoryDump
$want = if ($Restore) { if ($had) { [int]$old } else { $null } } else { 1 }

$out = @()
$out += ('readback AlwaysKeepMemoryDump=' + $val + ' want=' + $want + ' err=' + $err)
$ok = ($null -eq $want -and $null -eq $val) -or ($null -ne $want -and $val -eq $want)
$out += ('RESULT AlwaysKeepMemoryDump {0} -> {1} rc_ok={2}' -f $old, $val, $ok)
$out += ('VERDICT ' + $(if ($ok) { 'DUMPS_KEPT' } else { 'DUMPS_NOT_SET' }))
($out -join "`r`n") | Set-Content -LiteralPath (Join-Path $root 'temp\_p108_out.txt') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $root 'temp\_p108_out.txt')
