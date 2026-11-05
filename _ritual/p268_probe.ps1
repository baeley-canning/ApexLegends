# p268_probe.ps1 - isolate WHY guestcontrol run/copyfrom return nothing while copyto works.
# Raw stdout+stderr+rc of each step goes to its own file in _ritual. Read-only except t1/t2 files.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'; $U = 'vboxuser'; $P = 'password'
$b = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$g = 'C:\Users\Public\p37'
function Cap([string]$name, [string[]]$a) {
    $p = Join-Path $b ('p268x_' + $name + '.txt')
    $all = (& $VB @a 2>&1) | ForEach-Object { [string]$_ }
    ('rc=' + $LASTEXITCODE + ' lines=' + @($all).Count) + "`r`n" + ($all -join "`r`n") | Set-Content -LiteralPath $p -Encoding utf8
}
Cap 'ver'   @('--version')
Cap 'run'   @('guestcontrol', $VM, '--username', $U, '--password', $P, 'run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '60000', '--', 'cmd.exe', '/c', ('echo HELLO> ' + $g + '\t1.txt & dir /b ' + $g + ' > ' + $g + '\t2.txt & echo RAN'))
Cap 'copyfrom' @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', ($g + '\t2.txt'), (Join-Path $b 'p268x_t2.txt'))
Cap 'copyfrom2' @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', ($g + '\diag.out'), (Join-Path $b 'p268x_diag.txt'))
'probe done'
