$ErrorActionPreference = 'Continue'
$lg = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_post1.txt'
function Put($s) { Add-Content -LiteralPath $lg -Value ([string]$s) -Encoding utf8 }
function Cap($a) { return ((@($a) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join ' ~~ ') }
Remove-Item -LiteralPath $lg -ErrorAction SilentlyContinue
Put ('post1 ' + (Get-Date -Format s))
Put ('elev=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Put ('user=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Put ('lastboot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
Put ('startopts: ' + (Cap (& reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control' /v SystemStartOptions 2>&1)))
Put ('testsigning-honored: ' + [bool]((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions).SystemStartOptions -match 'TESTSIGNING'))
Put ('bcd: ' + (Cap (& bcdedit.exe 2>&1)))
Put '=== service start attempts ==='
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) {
    $out = Cap (& sc.exe start $s 2>&1)
    Put ('  start ' + $s + ' rc=' + $LASTEXITCODE + ' :: ' + $out)
    Start-Sleep -Milliseconds 800
    Put ('    q: ' + (Cap (& sc.exe query $s 2>&1)))
}
Put '=== CI events last 10 min ==='
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue | Sort-Object TimeCreated)) {
    Put ($e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + ($e.Message -replace '\s+', ' '))
}
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = (Get-Date).AddMinutes(-10); ProviderName = 'Service Control Manager' } -ErrorAction SilentlyContinue | Sort-Object TimeCreated)) {
    Put ('SCM ' + $e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + ($e.Message -replace '\s+', ' '))
}
Put ('done ' + (Get-Date -Format s))
