# p273_ga.ps1 - the guest was parked on "Automatic Repair" (armed logon trigger crash-looping
# it). After the keyboard restart, poll for the Additions and pull the hist tails the instant
# they answer, before the next logon-trigger bugcheck takes the box down again.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p273_ga.log'
function S($t) { ((Get-Date -f 'HH:mm:ss') + ' ' + $t) | Out-File -FilePath $log -Encoding utf8 -Append }
S 'poll start'
$hit = $false
$deadline = (Get-Date).AddSeconds(240)
while ((Get-Date) -lt $deadline) {
    $mi = (& $VB showvminfo $VM --machinereadable 2>&1) -join "`n"
    $lvl = ([regex]::Match($mi, 'GuestAdditionsRunLevel="(\d)"')).Groups[1].Value
    $st = ([regex]::Match($mi, 'VMState="(\w+)"')).Groups[1].Value
    S ('state=' + $st + ' ga=' + $lvl)
    if ($lvl -match '^[1-9]$') { $hit = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $hit) { S 'RESULT: ga never came up after repair restart'; exit 1 }
S 'ga up - pulling now'
& powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p37_gc.ps1' -Mode pull -N 269 2>&1 | Out-Null
S 'pull returned'
Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_gc.txt' -Tail 30 | ForEach-Object { S ('gc| ' + $_) }
S 'END'
