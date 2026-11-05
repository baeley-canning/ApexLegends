# p270_prep.ps1 - get the guest back to a state where guestcontrol works again.
# The restored snapshot booted into PCA modal dialogs (pcdsrvc / EchoDrv / nvoclk) and
# VBoxService never came up (GuestAdditionsRunLevel=0 for 2 min). Read-only w.r.t. drivers:
# this only dismisses dialogs and starts VBoxService inside the guest via the console.
# Run detached, log to p270_prep.txt, poll that file.
$ErrorActionPreference = 'Continue'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$d  = $PSScriptRoot
$lg = Join-Path $d 'p270_prep.txt'
function W($s) { (Get-Date -Format 'HH:mm:ss') + ' ' + $s | Add-Content $lg }

# VirtualBox scancode map (make codes only; break = +0x80, sent for Letter keys)
$map = @{
    'a'=0x1e;'b'=0x30;'c'=0x2e;'d'=0x20;'e'=0x12;'f'=0x21;'g'=0x22;'h'=0x23;'i'=0x17;'j'=0x24;'k'=0x25;'l'=0x26;'m'=0x32;
    'n'=0x31;'o'=0x18;'p'=0x19;'q'=0x10;'r'=0x13;'s'=0x1f;'t'=0x14;'u'=0x16;'v'=0x2f;'w'=0x11;'x'=0x2d;'y'=0x15;'z'=0x2c;
    ' '=0x39;'-'=0x0c;'.'=0x34;'\'=0x2b;':'=0x2a
}
function Keys($txt) {
    $seq = @()
    foreach ($ch in $txt.ToCharArray()) {
        $c = [string]$ch
        $k = $map[$c.ToLower()]
        if ($null -eq $k) { continue }
        $seq += ('{0:x2}' -f $k)
        $seq += ('{0:x2}' -f ($k + 0x80))
    }
    & $v controlvm Win11-Test2 keyboardputscancode @seq 2>&1 | Out-Null
}
function GaLevel {
    $o = (& $v showvminfo Win11-Test2 --machinereadable 2>&1) | Out-String
    $m = [regex]::Match($o, 'GuestAdditionsRunLevel=(\d)')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}

W 'START'

# 1) clear any PCA dialogs that come up after boot (they steal focus)
for ($i = 0; $i -lt 6; $i++) { & $v controlvm Win11-Test2 keyboardputscancode 01 81 2>&1 | Out-Null; Start-Sleep -Milliseconds 400 }
W 'dialogs dismissed'

$lvl = GaLevel
W ('ga=' + $lvl)
for ($i = 0; $i -lt 12 -and $lvl -lt 1; $i++) {
    Start-Sleep -Seconds 5
    $lvl = GaLevel
    W ('wait ' + $i + ' ga=' + $lvl)
}
if ($lvl -ge 1) { W 'GA_UP'; W 'END'; exit 0 }

# 2) still dead - console route: Win+R -> cmd -> sc start VBoxService
W 'fallback=console'
& $v controlvm Win11-Test2 keyboardputscancode 5b db 2>&1 | Out-Null
Start-Sleep -Milliseconds 1200
Keys 'cmd'
& $v controlvm Win11-Test2 keyboardputscancode 1c 9c 2>&1 | Out-Null
Start-Sleep -Seconds 3
& $v controlvm Win11-Test2 screenshotpng (Join-Path $d 'p270_prep_a.png') 2>&1 | Out-Null
Keys 'sc start VBoxService'
& $v controlvm Win11-Test2 keyboardputscancode 1c 9c 2>&1 | Out-Null
Start-Sleep -Seconds 6
& $v controlvm Win11-Test2 screenshotpng (Join-Path $d 'p270_prep_b.png') 2>&1 | Out-Null

for ($i = 0; $i -lt 10 -and $lvl -lt 1; $i++) {
    Start-Sleep -Seconds 5
    $lvl = GaLevel
    W ('post ' + $i + ' ga=' + $lvl)
}
W $(if ($lvl -ge 1) { 'GA_UP' } else { 'GA_DEAD' })
& $v controlvm Win11-Test2 screenshotpng (Join-Path $d 'p270_prep_c.png') 2>&1 | Out-Null
W 'END'
