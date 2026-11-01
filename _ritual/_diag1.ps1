$ErrorActionPreference = 'Continue'
$lg = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_diag1.txt'
$o = New-Object System.Collections.Generic.List[string]
$C = 'C:\Windows\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$st = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$o.Add('diag1 ' + (Get-Date -Format s))
$o.Add('testpath phantom=' + (Test-Path -LiteralPath "$C\apexdrv_p26.cat"))
$o.Add('filter-nostar=' + @(Get-ChildItem -LiteralPath $C -Filter 'apexdrv*' -EA SilentlyContinue).Count)
$o.Add('filter-star=' + @(Get-ChildItem -LiteralPath $C -Filter '*apexdrv*' -EA SilentlyContinue).Count)
$o.Add('getchild-all=' + @(Get-ChildItem -LiteralPath $C -EA SilentlyContinue).Count)
foreach ($x in @(Get-ChildItem -LiteralPath $C -Force -EA SilentlyContinue | Where-Object { $_.Name -like 'apexdrv*' })) {
    $o.Add('  entry ' + $x.Name + ' dir=' + $x.PSIsContainer + ' attrs=' + $x.Attributes + ' len=' + $x.Length + ' crt=' + $x.CreationTime.ToString('HH:mm:ss'))
}
$o.Add('--- CI events last 20min ---')
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).AddMinutes(-20)} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 260) { $m = $m.Substring(0, 260) }
    $o.Add($e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + $m)
}
$o.Add('--- bcd ---')
$o.Add(((bcdedit /enum '{current}') | Select-String -Pattern 'testsigning|nointegrity|hypervisorlaunchtype|vsmlaunchtype|flightsigning|description|identifier' | ForEach-Object { $_.ToString().Trim() }) -join ' | ')
$o.Add('--- secureboot ---')
try { $o.Add('secureboot=' + (Confirm-SecureBootUEFI)) } catch { $o.Add('secureboot=err:' + $_.Exception.Message) }
$o.Add('--- per-image /kp + /pa /c ---')
foreach ($p in @('C:\Windows\System32\drivers\apexdrv.sys', 'C:\p26cat\apexdrv_build.sys', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys')) {
    $ex = Test-Path -LiteralPath $p
    $o.Add('img ' + $p + ' exists=' + $ex + ' len=' + $(if ($ex) { (Get-Item -LiteralPath $p).Length } else { 0 }) + ' embedded=' + $(if ($ex) { (Get-AuthenticodeSignature -LiteralPath $p).Status } else { 'na' }))
    if ($ex) {
        $o.Add('  kp : ' + (((& $st verify /kp /c 'C:\p9\apexdrv_p9.cat' $p 2>&1) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join ' // '))
        $o.Add('  pac: ' + (((& $st verify /pa /c 'C:\p9\apexdrv_p9.cat' $p 2>&1) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join ' // '))
    }
}
$o.Add('--- own cat /kp ---')
$o.Add((((& $st verify /kp 'C:\p9\apexdrv_p9.cat' 2>&1) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join ' // '))
$o.Add('--- cert files under working dirs ---')
$o.Add((@(Get-ChildItem -Path @('C:\p9', 'C:\p8', 'C:\p26cat', 'C:\Users\New User\OneDrive\Desktop\cheating') -Recurse -Depth 2 -Include *.cer, *.crt, *.p7b, *.pfx -EA SilentlyContinue | Select-Object -First 25 | ForEach-Object { $_.FullName + '(' + $_.Length + ')' }) -join ' ; ')
$o.Add('--- MS cross/root in machine stores ---')
$o.Add((@(Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue | Where-Object { $_.Subject -match 'Code Verification|Microsoft Root Certificate' } | ForEach-Object { 'R ' + $_.Subject }) -join ' ; ')
$o.Add((@(Get-ChildItem Cert:\LocalMachine\CA -EA SilentlyContinue | Where-Object { $_.Subject -match 'Code Verification' } | ForEach-Object { 'I ' + $_.Subject }) -join ' ; ')
$o.Add('--- personal certs with keys ---')
$o.Add((@(Get-ChildItem Cert:\LocalMachine\My, Cert:\CurrentUser\My -EA SilentlyContinue | ForEach-Object { 'my ' + $_.Subject + ' priv=' + $_.HasPrivateKey + ' exp=' + $_.NotAfter.ToString('yyyy-MM') }) -join ' ; ')
$o.Add('--- elevated fresh start attempts ---')
$t1 = Get-Date
$inner = '-NoProfile -ExecutionPolicy Bypass -Command "& { foreach ($s in ''apexdrv'',''apexdrv_cat'',''kernprobe'') { $r = (sc.exe start $s 2>&1) -join '' ''; Write-Output ($s + '' -> '' + $r) }; sc.exe stop apexdrv; sc.exe stop apexdrv_cat; sc.exe stop kernprobe }"'
try { Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -Wait -ArgumentList $inner -EA Stop } catch { $o.Add('elevate-err: ' + $_.Exception.Message) }
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) { $o.Add('state ' + $s + ': ' + (((sc.exe query $s 2>&1) -join ' '))) }
$o.Add('--- CI events since fresh start (' + $t1.ToString('HH:mm:ss') + ') ---')
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = $t1} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 400) { $m = $m.Substring(0, 400) }
    $o.Add($e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + $m)
}
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = $t1; ProviderName = 'Service Control Manager'} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 300) { $m = $m.Substring(0, 300) }
    $o.Add('SCM ' + $e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + $m)
}
$o.Add('done ' + (Get-Date -Format s))
$o | Set-Content -LiteralPath $lg -Encoding utf8
'wrote ' + $lg + ' lines=' + $o.Count
