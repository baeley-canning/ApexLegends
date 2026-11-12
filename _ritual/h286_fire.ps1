# h286_fire.ps1 - standalone tick fire. The deploy script was killed by shell flake after its
# read-back and BEFORE the schtasks call (h286_deploy.txt ends at 'post listen8080=1'), so the
# guest never ran. This is only the fire step, isolated with a 30 s cap per attempt so it cannot
# hang a session, output to its own file (R5). Passwords tried in HANDOFF order, then vboxuser.
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h286_fire.txt'
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function TryFire([string]$pw, [string]$label) {
    $so = "$env:TEMP\h286_stdo.txt"; $se = "$env:TEMP\h286_stde.txt"
    $p = Start-Process -FilePath schtasks.exe -ArgumentList '/run','/tn','p37tick','/s','192.168.56.101','/u','vboxuser','/p',$pw -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    if ($p.WaitForExit(30000)) {
        $t = ((Get-Content $so -Raw -EA 0) + (Get-Content $se -Raw -EA 0) -replace '\s+', ' ').Trim()
        W ($label + ' rc=' + $p.ExitCode + ' out=[' + $t + ']')
        return ($p.ExitCode -eq 0)
    }
    try { $p.Kill() } catch { }
    W ($label + ' TIMEOUT after 30 s (killed)')
    return $false
}
W '=== h286 fire: schtasks /run /tn p37tick /s 192.168.56.101 ==='
if (TryFire 'password' 'fire[pw=password]')      { W 'RESULT: FIRED with pw=password' }
elseif (TryFire 'vboxuser' 'fire[pw=vboxuser]')   { W 'RESULT: FIRED with pw=vboxuser' }
else                                              { W 'RESULT: FIRE FAILED both passwords - next: guestcontrol trigger or controlvm reset' }
W 'VERDICT: poll C:\p37vm\guest-h286.log'
