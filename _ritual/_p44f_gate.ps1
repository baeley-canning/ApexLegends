# p44f gate: staging parity, compile, env-override proof -- written to a file
# because this terminal's shell integration drops console capture.
$repo   = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out    = Join-Path $repo '_ritual\_p44f_gate.txt'
$staged = 'C:\Windows\Temp\p44f_run.ps1'
$src    = Join-Path $repo 'temp\c55_run_new.ps1'
$py     = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$a = @()
$hs = if (Test-Path -LiteralPath $staged) { (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash } else { 'MISSING' }
$ho = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
$a += 'staged ' + $hs
$a += 'source ' + $ho
$a += 'parity ' + ($hs -eq $ho)
& $py -m py_compile (Join-Path $repo 'ext\basehunt.py') 2>&1 | ForEach-Object { $a += 'pyc ' + $_ }
$rc1 = $LASTEXITCODE
$a += 'py_compile rc=' + $rc1
$probe = & $py -c "import os,sys; os.environ['DUMP_LINK']='0xdeadbeef'; os.environ['DUMP_FL']='0x1111'; os.environ['DUMP_BL']='0x2222'; sys.path.insert(0, r'$repo\ext'); import basehunt as b; print('link=%#x fl=%#x bl=%#x pid=%#x' % (b.LINK, b.NODE_FL, b.NODE_BL, b.PID))" 2>&1
$a += 'env_probe ' + ($probe -join ' | ')
$ok = ($hs -eq $ho) -and ($rc1 -eq 0) -and (($probe -join '') -like '*link=0xdeadbeef*')
$a += 'RESULT: ' + $(if ($ok) { 'GATE_OK' } else { 'GATE_FAIL' })
$a | Set-Content -LiteralPath $out -Encoding utf8
Write-Host ($a -join [Environment]::NewLine)
