# p270_boot.ps1 - the guest fell into "Automatic Repair / Your PC did not start correctly"
# during p270_prep (boot-time crash loop suspect). Power-cycle it and watch the boot:
# poll GA runlevel, screenshot every 15 s so the log is self-explanatory if it loops.
# Read-only w.r.t. drivers. Foreground; poll p270_boot.txt and the shots with read_files only.
$ErrorActionPreference = 'Continue'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$d  = $PSScriptRoot
$lg = Join-Path $d 'p270_boot.txt'
function W($s) { (Get-Date -Format 'HH:mm:ss') + ' ' + $s | Add-Content $lg }
function GaLevel {
    $o = (& $v showvminfo Win11-Test2 --machinereadable 2>&1) | Out-String
    $m = [regex]::Match($o, 'GuestAdditionsRunLevel=(\d)')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}

W 'START'
& $v controlvm Win11-Test2 reset 2>&1 | Out-Null
W 'reset sent'
$lvl = -1
for ($i = 0; $i -lt 16 -and $lvl -lt 1; $i++) {
    Start-Sleep -Seconds 15
    $lvl = GaLevel
    & $v controlvm Win11-Test2 screenshotpng (Join-Path $d ('p270_boot_' + $i + '.png')) 2>&1 | Out-Null
    W ('t=' + (($i + 1) * 15) + 's ga=' + $lvl)
}
W $(if ($lvl -ge 1) { 'GA_UP' } else { 'GA_DEAD' })
W 'END'
