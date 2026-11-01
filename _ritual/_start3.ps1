$ErrorActionPreference = 'Continue'
$o = New-Object System.Collections.Generic.List[string]
$o.Add('start3 ' + (Get-Date -Format s))
$o.Add('authz=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) {
    $r = (& sc.exe start $s 2>&1) -join ' | '
    $o.Add('start ' + $s + ' -> rc=' + $LASTEXITCODE + ' out=' + $r)
    Start-Sleep -Milliseconds 700
    $o.Add('  q: ' + ((& sc.exe query $s 2>&1) -join ' | '))
}
Start-Sleep -Milliseconds 400
$o.Add('--- stop/cleanup ---')
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) { $o.Add('stop ' + $s + ': ' + ((& sc.exe stop $s 2>&1) -join ' | ')) }
$o | Set-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_start3.txt' -Encoding utf8
