$ErrorActionPreference = 'Continue'
$lg = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_diag3.txt'
$o = New-Object System.Collections.Generic.List[string]
$C = 'C:\Windows\System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
function Put($s) { $o.Add([string]$s) }
Put('diag3 ' + (Get-Date -Format s))
$t = (Get-Date).AddMinutes(-10)
foreach ($e in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = $t} -EA SilentlyContinue | Sort-Object TimeCreated)) {
    Put('== ' + $e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id)
    Put(($e.Message -replace '\s+', ' '))
    $i = 0
    foreach ($p in $e.Properties) { Put('   p[' + $i + '] ' + ([string]$p.Value -replace '\s+', ' ')); $i++ }
    Put('   xml: ' + ($e.ToXml() -replace '\s+', ' '))
}
Put('--- services config ---')
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) { Put('qc ' + $s + ': ' + (((& sc.exe qc $s 2>&1)) -join ' | ')) }
Put('--- store anatomy ---')
Put('store subdirs=' + @(Get-ChildItem -LiteralPath $C -Directory -EA SilentlyContinue).Count)
foreach ($d in @(Get-ChildItem -LiteralPath $C -Directory -EA SilentlyContinue | Select-Object -First 25)) { Put('  sd ' + $d.Name + ' attrs=' + $d.Attributes) }
foreach ($f in @(Get-ChildItem -LiteralPath $C -File -EA SilentlyContinue | Select-Object -First 4)) { Put('  cat ' + $f.Name + ' attrs=' + $f.Attributes + ' len=' + $f.Length) }
Put('--- CatRoot2 ---')
$c2 = 'C:\Windows\System32\CatRoot2'
Put('catroot2 exists=' + (Test-Path -LiteralPath $c2))
foreach ($d in @(Get-ChildItem -LiteralPath $c2 -Directory -EA SilentlyContinue)) { Put('  d2 ' + $d.Name + ' entries=' + @(Get-ChildItem -LiteralPath $d.FullName -EA SilentlyContinue).Count + ' apex=' + @(Get-ChildItem -LiteralPath $d.FullName -Filter '*apex*' -EA SilentlyContinue).Count) }
Put('--- apex cats anywhere under CatRoot* ---')
foreach ($p in @(Get-ChildItem -LiteralPath $C -EA SilentlyContinue | Where-Object { $_.Name -like '*apex*' })) { Put('  hit ' + $p.FullName + ' dir=' + $p.PSIsContainer) }
Put('--- apex cats in CatRoot2 tree ---')
foreach ($p in @(Get-ChildItem -LiteralPath $c2 -Recurse -Depth 1 -EA SilentlyContinue | Where-Object { $_.Name -like '*apex*' } | Select-Object -First 10)) { Put('  h2 ' + $p.FullName) }
Put('--- boot / DSE policy state ---')
Put('startopts=' + [string]((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SystemStartOptions' -EA SilentlyContinue).SystemStartOptions))
Put('sbstate=' + [string]((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA SilentlyContinue).UEFISecureBootEnabled))
Put('ci-subkeys=' + (@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\CI' -EA SilentlyContinue | Select-Object -ExpandProperty PSChildName) -join ','))
Put('bcdedit: ' + (((& bcdedit.exe /enum '{current}' 2>&1) -join ' ~ ')))
Put('--- distinct CI event ids last 6h ---')
foreach ($g in @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).AddHours(-6) } -EA SilentlyContinue | Group-Object Id)) { Put('  id=' + $g.Name + ' n=' + $g.Count + ' first=' + $g.Group[0].TimeCreated.ToString('HH:mm:ss') + ' :: ' + ($g.Group[0].Message -replace '\s+', ' ')) }
Put('--- kernel-policy check of own cat vs deployed file ---')
$st = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
Put('kp-cat: ' + (((& $st verify /kp /c C:\p9\apexdrv_p9.cat 'C:\Windows\System32\drivers\apexdrv.sys' 2>&1) -join ' // ')))
Put('--- on-disk hashes ---')
foreach ($f in @('C:\Windows\System32\drivers\apexdrv.sys', 'C:\p26cat\apexdrv_build.sys')) { if (Test-Path -LiteralPath $f) { Put('  h ' + $f + ' sha1=' + (Get-FileHash -LiteralPath $f -Algorithm SHA1).Hash + ' sha256=' + (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash) } }
Put('done ' + (Get-Date -Format s))
$o | Set-Content -LiteralPath $lg -Encoding utf8
