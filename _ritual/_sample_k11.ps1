# _sample_k11.ps1 - one passive sample, then exit. Read-only.
# Scheduled by schtasks /SC MINUTE (durable); each fire appends one line.
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_plan_k11watch.txt'
$log = 'C:\p37vm\guest-k11.log'
$sig = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_plan_sig11.txt'
$hb  = @(Select-String -Path $log -Pattern '^HB ').Count
$s   = @(Get-Content $sig -ErrorAction SilentlyContinue).Count
$st  = (Get-ScheduledTask -TaskName p37_sig11r -ErrorAction SilentlyContinue).State
$last = (Select-String -Path $log -Pattern '^HB ' | Select-Object -Last 1).Line
('{0} hb={1} sig={2} task={3} | {4}' -f (Get-Date -f 'HH:mm:ss'), $hb, $s, $st, $last) |
    Out-File -Encoding utf8 -Append $out
