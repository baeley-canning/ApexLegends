# p270_gc.ps1 - guestcontrol with retries. GA session start is flaky on this box ("current status
# is: starting" repeats while a PCA dialog stack is up), so every call retries before it is declared
# dead. Read-only unless -Action says otherwise.
param(
    [ValidateSet('run', 'copyfrom', 'copyto')][string]$Action = 'run',
    [string]$Exe = '',
    [string]$Args = '',
    [string]$From = '',
    [string]$To = '',
    [int]$Tries = 6,
    [int]$GapMs = 3000,
    [int]$TimeoutMs = 60000
)
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'; $U = 'vboxuser'; $P = 'password'
$log = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_gc.txt'
Remove-Item -LiteralPath $log -EA 0
for ($i = 1; $i -le $Tries; $i++) {
    switch ($Action) {
        'run' {
            $a = @('guestcontrol', $VM, '--username', $U, '--password', $P, 'run', '--exe', $Exe,
                   '--wait-stdout', '--wait-stderr', '--timeout', "$TimeoutMs", '--')
            $a += $Exe
            if ($Args) { $a += ($Args -split '\|') }
        }
        'copyfrom' { $a = @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', $From, $To) }
        'copyto'   { $a = @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyto', $From, $To) }
    }
    $out = (& $VB @a 2>&1) | ForEach-Object { [string]$_ }
    $rc = $LASTEXITCODE
    ("try={0} rc={1} " -f $i, $rc) + (($out -join ' | ') -replace '\s+', ' ') | Add-Content -LiteralPath $log
    $blob = ($out -join "`n")
    if ($blob -notmatch 'Error starting guest session' -and $blob -notmatch 'startup failed' -and
        $blob -notmatch 'not installed or not ready' -and $blob -notmatch 'VBOX_E_GSTCTL_GUEST_ERROR') {
        ($out -join "`r`n") | Add-Content -LiteralPath $log
        "OK after $i" | Add-Content -LiteralPath $log
        exit 0
    }
    if ($i -lt $Tries) { Start-Sleep -Milliseconds $GapMs }
}
"GAVE UP" | Add-Content -LiteralPath $log
exit 1
