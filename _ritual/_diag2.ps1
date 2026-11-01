$ErrorActionPreference = 'Continue'
$lg = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_diag2.txt'
$o = New-Object System.Collections.Generic.List[string]
$C = 'C:\Windows\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$st = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$cat = 'C:\p9\apexdrv_p9.cat'
function Cap($a) { return ((@($a) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join ' // ') }
function Put($s) { $o.Add([string]$s) }
function Join2($a) { return ((@($a) | ForEach-Object { [string]$_ }) -join ' ; ') }

Put ('diag2 ' + (Get-Date -Format s))
Put('testpath phantom=' + (Test-Path -LiteralPath "$C\apexdrv_p26.cat"))
Put('filter-nostar=' + @(Get-ChildItem -LiteralPath $C -Filter 'apexdrv*' -EA SilentlyContinue).Count)
Put('filter-star=' + @(Get-ChildItem -LiteralPath $C -Filter '*apexdrv*' -EA SilentlyContinue).Count)
Put('getchild-all=' + @(Get-ChildItem -LiteralPath $C -EA SilentlyContinue).Count)
foreach ($x in @(Get-ChildItem -LiteralPath $C -Force -EA SilentlyContinue | Where-Object { $_.Name -like 'apexdrv*' })) {
    Put('  entry ' + $x.Name + ' dir=' + $x.PSIsContainer + ' attrs=' + $x.Attributes + ' len=' + $x.Length + ' crt=' + $x.CreationTime.ToString('HH:mm:ss'))
}
Put('--- CI events last 20min ---')
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).AddMinutes(-20)} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 260) { $m = $m.Substring(0, 260) }
    Put($e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + $m)
}
Put('--- bcd ---')
Put(Join2 ((bcdedit /enum '{current}') | Select-String -Pattern 'testsigning|nointegrity|hypervisorlaunchtype|vsmlaunchtype|flightsigning|description|identifier' | ForEach-Object { $_.ToString().Trim() }))
Put('--- secureboot ---')
try { Put('secureboot=' + (Confirm-SecureBootUEFI)) } catch { Put('secureboot=err:' + $_.Exception.Message) }
Put('--- per-image /kp + /pa /c ---')
foreach ($p in @('C:\Windows\System32\drivers\apexdrv.sys', 'C:\p26cat\apexdrv_build.sys', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys')) {
    $ex = Test-Path -LiteralPath $p
    Put('img ' + $p + ' exists=' + $ex + ' len=' + $(if ($ex) { (Get-Item -LiteralPath $p).Length } else { 0 }) + ' embedded=' + $(if ($ex) { (Get-AuthenticodeSignature -LiteralPath $p).Status } else { 'na' }))
    if ($ex) {
        Put('  kp  : ' + (Cap (& $st verify /kp /c $cat $p 2>&1)))
        Put('  pac : ' + (Cap (& $st verify /pa /c $cat $p 2>&1)))
    }
}
Put('own cat verify /kp: ' + (Cap (& $st verify /kp $cat 2>&1)))
Put('--- cert files under working dirs ---')
Put(Join2 (@(Get-ChildItem -Path @('C:\p9', 'C:\p8', 'C:\p26cat', 'C:\Users\New User\OneDrive\Desktop\cheating') -Recurse -Depth 2 -Include *.cer, *.crt, *.p7b, *.pfx -EA SilentlyContinue | Select-Object -First 25 | ForEach-Object { $_.FullName + '(' + $_.Length + ')' })))
Put('--- MS cross/root in machine stores ---')
Put(Join2 (@(Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue | Where-Object { $_.Subject -match 'Code Verification|Microsoft Root Certificate' } | ForEach-Object { 'R ' + $_.Subject })))
Put(Join2 (@(Get-ChildItem Cert:\LocalMachine\CA -EA SilentlyContinue | Where-Object { $_.Subject -match 'Code Verification' } | ForEach-Object { 'I ' + $_.Subject })))
Put('--- personal certs with keys ---')
Put(Join2 (@(Get-ChildItem Cert:\LocalMachine\My, Cert:\CurrentUser\My -EA SilentlyContinue | ForEach-Object { 'my ' + $_.Subject + ' priv=' + $_.HasPrivateKey + ' exp=' + $_.NotAfter.ToString('yyyy-MM') })))
Put('--- elevated fresh start attempts ---')
$t1 = Get-Date
try { Start-Process -FilePath 'C:\p9\_start3.cmd' -Verb RunAs -Wait -EA Stop } catch { Put('elevate-err: ' + $_.Exception.Message) }
Start-Sleep -Milliseconds 900
if (Test-Path -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_start3.txt') { foreach ($l in (Get-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_start3.txt')) { Put('child ' + $l) } } else { Put('child log missing') }

foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) { Put('state ' + $s + ': ' + (Cap (& sc.exe query $s 2>&1))) }
Put('--- CI events since fresh start (' + $t1.ToString('HH:mm:ss') + ') ---')
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = $t1} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 400) { $m = $m.Substring(0, 400) }
    Put($e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + $m)
}
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = $t1; ProviderName = 'Service Control Manager'} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 300) { $m = $m.Substring(0, 300) }
    Put('SCM ' + $e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + $m)
}
Put('done ' + (Get-Date -Format s))
$o | Set-Content -LiteralPath $lg -Encoding utf8
'wrote ' + $lg + ' lines=' + $o.Count
