# p284_key.ps1 - probe #284 (variable: is the guest accepting ANY keystroke at all)
# Since the #281 reboot the desktop takes 'win' but no characters: Start stays open with an empty
# search box across minutes of injected payload. Before writing another command probe, test the
# two cheap observables: does ESC close the flyout, does a letter land in the search box.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p284.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d ('p284_' + $n + '.png')) 2>&1 | Out-Null; Say ('shot ' + $n) }

Say 'START'
Shot 'before'
K @('esc'); Start-Sleep -Milliseconds 1500
Shot 'after_esc'
K @('a'); Start-Sleep -Milliseconds 1500
Shot 'after_a'
K @('b','c'); Start-Sleep -Milliseconds 1200
Shot 'after_bc'
Say 'END'
