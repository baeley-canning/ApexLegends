# p270_watch.ps1 - the guest boots to the desktop, crash-loops (0x3B), and falls back to
# Automatic Repair. GA never gets a chance because the window is short and nothing starts
# VBoxService. This watches the boot at 3 s granularity: logs runlevel, shots every 20 s,
# and the moment a desktop-capable state shows up (ga>=1) it fires winr -> cmd -> sc start
# vboxservice once. Then it keeps polling to prove GA stayed up.
# Read-only. Keystrokes go through vm_type.ps1 because `sc` collides with the Set-Content alias.
param([int]$Ticks = 100)
$ErrorActionPreference = 'Continue'
$v = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$d = $PSScriptRoot
$lg = Join-Path $d 'p270_watch.txt'
function W($s) { ((Get-Date -Format 'HH:mm:ss') + ' ' + $s) | Add-Content -LiteralPath $lg }
function Shot($n) { & $v controlvm Win11-Test2 screenshotpng (Join-Path $d $n) 2>&1 | Out-Null }
function GaLevel {
    $o = (& $v showvminfo Win11-Test2 --machinereadable 2>&1) | Out-String
    $m = [regex]::Match($o, 'GuestAdditionsRunLevel=(\d)')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}

W ('START ticks=' + $Ticks)
$fired = $false
$up = 0
for ($i = 0; $i -lt $Ticks; $i++) {
    Start-Sleep -Seconds 3
    $lvl = GaLevel
    if ($lvl -ge 1) { $up++ }
    W ('t=' + (($i + 1) * 3) + 's ga=' + $lvl)
    if ((($i + 1) % 7) -eq 0) { Shot ('p270_w_' + $i + '.png') }
    if (-not $fired -and $lvl -ge 1) {
        $fired = $true
        W 'desktop detected, arming GA via console'
        & (Join-Path $d 'vm_type.ps1') -Seq @('winr')
        Start-Sleep -Milliseconds 1500
        & (Join-Path $d 'vm_type.ps1') -Seq @('cmd', 'enter')
        Start-Sleep -Seconds 3
        Shot 'p270_w_cmd.png'
        & (Join-Path $d 'vm_type.ps1') -Seq @('sc start vboxservice', 'enter')
        Start-Sleep -Seconds 6
        Shot 'p270_w_start.png'
        W ('post-ga ga=' + (GaLevel))
    }
}
W ('ga_up_ticks=' + $up)
W $(if ($up -ge 3) { 'GA_UP' } else { 'GA_DEAD' })
Shot 'p270_w_end.png'
W 'END'
