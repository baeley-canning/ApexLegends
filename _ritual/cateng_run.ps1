$d = $PSScriptRoot
& (Join-Path $d 'cateng.ps1') -SelfTest *> (Join-Path $d 'selftest_console.txt')
Copy-Item -Force (Join-Path $d 'cateng.txt') (Join-Path $d 'cateng_selftest.txt')
$f = @((Join-Path $d '_p25h_S6lan.sys'), "$env:SystemRoot\System32\drivers\apexdrv.sys", "$env:SystemRoot\System32\drivers\tcpip.sys")
& (Join-Path $d 'cateng.ps1') -Path $f -Lookup *> (Join-Path $d 'lookup_console.txt')
Copy-Item -Force (Join-Path $d 'cateng.txt') (Join-Path $d 'cateng_lookup.txt')
'run-complete' | Set-Content -Encoding utf8 (Join-Path $d 'run_complete.txt')
