# Guest ONLY: first snapshot, validated build bytes, read-only test whose receipt
# is pulled back. On no VM or load error restore the ready snapshot, no host.
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm = 'Win11-Test2'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h394_vm_bench2.txt'
function v([string[]]$a, [int]$limit=60000) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $vb; $psi.UseShellExecute=$false
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.Arguments = (($a | ForEach-Object { if ($_ -match '\\s') {'"'+$_+'"'} else {$_} }) -join ' ')
    $p=[Diagnostics.Process]::Start($psi); $o=$p.StandardOutput.ReadToEndAsync(); $e=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit($limit)){try{$p.Kill()}catch{}; return 'TIMEOUT'}
    return ($o.Result+' '+$e.Result)
}
function w([string]$s){((Get-Date -Format 'HH:mm:ss.fff')+' '+$s)|Add-Content -LiteralPath $log;Write-Host $s}
w ('state='+(v @('showvminfo',$vm,'--machinereadable') -match 'VMState='))
'pre_h394_v16_read' | Set-Content "$env:TEMP\h394_snap.txt"
$sources = @('C:\apexdrv.sys', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\qk_probe.exe',
             'C:\Users\New User\OneDrive\Desktop\cheating\temp\h394_v16_guest.ps1')
foreach ($f in $sources) {if(-not(Test-Path $f)){w("MISSING $f"); Stop-Transcript; exit 3}}
$g=@('guestcontrol',$vm)
$ready=v ($g+@('run','--exe','C:\Windows\System32\cmd.exe','--username','vboxuser','--password','password','--wait-stdout','--','/c','echo READY'))
w ('ready='+$ready)
& $vb guestcontrol $vm mkdir --parents 'C:\h394' --username vboxuser --password password 2>&1 | Out-String | Add-Content $log
foreach($f in $sources){w(v($g+@('copyto',$f,'--target-directory',('C:\'+(Split-Path $f -Leaf)),'--username','vboxuser','--password','password')))}
w ('run='+(v ($g+@('run','--exe','C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe','--username','vboxuser','--password','password','--wait-stdout','--','-NoProfile','-ExecutionPolicy','Bypass','-File','C:\h394_v16_guest.ps1')) 300000))
w ('pull='+(v($g+@('copyfrom','C:\h394_v16_out.txt','--target-directory','C:\Users\New User\OneDrive\Desktop\cheating\temp\h394_v16_guest.out','--username','vboxuser','--password','password'))))
w ('pull self='+(v($g+@('copyfrom','C:\h394_probe_self.txt','--target-directory','C:\Users\New User\OnDrive\Desktop\cheating\temp\h394_probe_self.txt','--username','vboxuser','--password','password'))))
v ($g+@('run','--exe','C:\Windows\System32\sc.exe','--username','vboxuser','--password','password','--wait-stdout','--','stop','ApexDrv')) | Add-Content $log
w 'guest chain complete (see h394_v16_guest.out)'