param([string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\resmap.txt')
# resmap.ps1 - decode HKLM\HARDWARE\RESOURCEMAP\System Resources\Physical Memory\.Translated
# Gives the REAL physical RAM ranges (incl. MMIO holes).  gdrv3 maps a PA without
# validating backing RAM, so this is the correct InRam() mask - "PA < ramTop" is NOT,
# because on a 32 GB box the PCI/MMIO hole sits BELOW ramTop.
# Emits a machine-readable RAMRANGES=start-end,start-end,... line for p36_prov.cs.
$o = $Out
function S($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }

S ("resmap {0}  host={1}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'), $env:COMPUTERNAME)
$b = $null
try {
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('HARDWARE\RESOURCEMAP\System Resources\Physical Memory')
    $b = $k.GetValue('.Translated')
    $k.Close()
} catch { S ("  open ERR: " + $_.Exception.Message) }
if ($null -eq $b) { S '  .Translated MISSING' }
elseif ($b.Length -lt 16) { S ("  raw bytes={0} hex={1}" -f $b.Length, (($b | ForEach-Object { $_.ToString('x2') }) -join ' ')) }
else {
    # CM_RESOURCE_LIST: Count(4) InterfaceType(4) BusNumber(4) Version(2) Revision(2) Count(4) [desc16]*
    $off = 0
    $count = [BitConverter]::ToUInt32($b, $off); $off += 4
    S ("  raw bytes={0}  list count={1}" -f $b.Length, $count)
    $ranges = New-Object System.Collections.ArrayList
    for ($l = 0; $l -lt $count; $l++) {
        if ($off + 16 -gt $b.Length) { break }
        $off += 8                                   # InterfaceType, BusNumber
        $off += 4                                   # Version, Revision
        $n = [BitConverter]::ToUInt32($b, $off); $off += 4
        S ("  list[$l] descriptors=$n")
        for ($d = 0; $d -lt $n; $d++) {
            if ($off + 16 -gt $b.Length) { break }
            $type  = $b[$off]
            $flags = [BitConverter]::ToUInt16($b, $off + 2)
            $start = [BitConverter]::ToUInt64($b, $off + 4)
            $len   = [BitConverter]::ToUInt32($b, $off + 12)
            $off += 16
            S ("    desc[$d] type={0} flags=0x{1:x} start=0x{2:x} len=0x{3:x} end=0x{4:x}" -f $type, $flags, $start, $len, ($start + $len))
            if ($type -eq 3 -and $len -gt 0) { $ranges.Add(('{0:x}-{1:x}' -f $start, ($start + $len))) | Out-Null }
        }
    }
    S ("  bytes consumed = $off of " + $b.Length)
    S ("RAMRANGES=" + ($ranges -join ','))
}
S '--- summary ---'
$total = 0
Get-CimInstance Win32_PhysicalMemory -EA 0 | ForEach-Object { $total += [int64]$_.Capacity }
S ("  sticks total = 0x{0:x} ({1} GB)" -f $total, [math]::Round($total / 1GB, 2))
S ("  TotalPhysicalMemory = 0x{0:x}" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory))
S ("  TotalVisibleMemorySize = 0x{0:x}" -f (((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize) * 1024))
S '--- end ---'
