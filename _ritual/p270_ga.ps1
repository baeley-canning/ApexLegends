# p270_ga.ps1 - GA is still runlevel 0 although the guest reached a real desktop
# (p270_boot_*.png). Retry the console route against that desktop: Win+R -> cmd ->
# "sc start VBoxService", then poll the runlevel and screenshot each step.
# Read-only w.r.t. drivers. Foreground; poll p270_ga.txt + shots with read_files only.
$ErrorActionPreference = 'Continue'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$d  = $PSScriptRoot
$lg = Join-Path $d 'p270_ga.txt'
function W($s) { (Get-Date -Format 'HH:mm:ss') + ' ' + $s | Add-Content $lg }
function Shot($n) { & $v controlvm Win11-Test2 screenshotpng (Join-Path $d $n) 2>&1 | Out-Null }
function Sc($h) { & $v controlvm Win11-Test2 keyboardputscancode $h 2>&1 | Out-Null }
function Type($t) {
    $map = @{
        'a'=0x1E;'b'=0x30;'c'=0x2E;'d'=0x20;'e'=0x12;'f'=0x21;'g'=0x22;'h'=0x23;'i'=0x17;'j'=0x24;'k'=0x25;'l'=0x26;'m'=0x32
        'n'=0x31;'o'=0x18;'p'=0x19;'q'=0x10;'r'=0x13;'s'=0x1F;'t'=0x14;'u'=0x16;'v'=0x2F;'w'=0x11;'x'=0x2D;'y'=0x15;'z'=0x2C
        ' '=0x39;'.'=0x34;'-'=0x0C
    }
    foreach ($ch in $t.ToCharArray()) {
        $c = ([string]$ch).ToLower()
        if ($map.ContainsKey($c)) {
            Sc ('{0:x2} {1:x2}' -f $map[$c], ($map[$c] + 0x80))
            Start-Sleep -Milliseconds 35
        }
    }
}
function GaLevel {
    $o = (& $v showvminfo Win11-Test2 --machinereadable 2>&1) | Out-String
    $m = [regex]::Match($o, 'GuestAdditionsRunLevel=(\d)')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}

W 'START'
# clear any PCA dialog that reappeared over the desktop
for ($i = 0; $i -lt 4; $i++) { Sc '01 81'; Start-Sleep -Milliseconds 400 }
W 'esc sent'
Shot 'p270_ga_0.png'

# Win+R -> cmd -> Enter
Sc '5b db'
Start-Sleep -Milliseconds 1200
Type 'cmd'
Sc '1c 9c'
Start-Sleep -Seconds 3
Shot 'p270_ga_1.png'
W 'cmd sent'

Type 'sc start VBoxService'
Sc '1c 9c'
Start-Sleep -Seconds 6
Shot 'p270_ga_2.png'
W 'sc start sent'

Type 'sc query vboxservice'
Sc '1c 9c'
Start-Sleep -Seconds 4
Shot 'p270_ga_3.png'
W 'sc query sent'

$lvl = GaLevel
W ('ga=' + $lvl)
for ($i = 0; $i -lt 20 -and $lvl -lt 1; $i++) {
    Start-Sleep -Seconds 5
    $lvl = GaLevel
    W ('wait ' + $i + ' ga=' + $lvl)
}
W $(if ($lvl -ge 1) { 'GA_UP' } else { 'GA_DEAD' })
Shot 'p270_ga_4.png'
W 'END'
