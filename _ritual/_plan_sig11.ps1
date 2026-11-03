# _plan_sig11.ps1 - one compact, append-only soak signature per call. Read-only.
$o = Join-Path $PSScriptRoot '_plan_sig11.txt'
$g = 'C:\p37vm\guest-k11.log'
$hb = @(Select-String -Path $g -Pattern '^HB ' -EA 0)
$last = if ($hb) { $hb[-1].Line } else { 'none' }
$st = ((& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' showvminfo VM-D --machinereadable 2>&1) | Select-String '^VMState=')
$res = @(Select-String -Path $g -Pattern 'RESULT: SOAK' -EA 0)
$sig = (Get-Date -f 'HH:mm:ss') + ' vm=' + ($st.Line -replace 'VMState=', '').Trim('"') +
       ' hb=' + $hb.Count + ' [' + $last + ']' +
       ' result=' + $(if ($res) { $res[-1].Line } else { '-' })
$sig | Out-File -FilePath $o -Encoding ascii -Append
