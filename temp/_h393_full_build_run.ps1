$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$c = 'C:\BuildTools\VC\Tools\MSVC\14.44.35207'
$k = 'C:\Program Files (x86)\Windows Kits\10'
$v = '10.0.26100.0'
$kind = $args[0]; if (-not $kind) { $kind = 'query' }
if ($kind -eq 'query') { $name = 'qk_process_query' } else { $name = 'h393_pfn_control' }
& "$c\bin\Hostx64\x64\cl.exe" /nologo /c /W4 /EHsc /MT /O2 /D_WIN32_WINNT=0x0A00 `
  "/Fo$r\QwenKernPremium\build\obj\$name.obj" "/I$c\include" `
  "/I$k\Include\$v\um" "/I$k\Include\$v\shared" "/I$k\Include\$v\ucrt" `
  "$r\QwenKernPremium\tools\$name.cpp" *> "$r\temp\_h393_${name}_build.txt"
if ($LASTEXITCODE) { Get-Content "$r\temp\_h393_${name}_build.txt" -Encoding Unicode; exit 1 }
& "$c\bin\Hostx64\x64\link.exe" /nologo /MACHINE:X64 /SUBSYSTEM:CONSOLE /INCREMENTAL:NO `
  "/OUT:$r\QwenKernPremium\build\$name.exe" "$r\QwenKernPremium\build\obj\$name.obj" `
  kernel32.lib ntdll.lib "/LIBPATH:$c\lib\x64" "/LIBPATH:$k\Lib\$v\um\x64" `
  "/LIBPATH:$k\Lib\$v\ucrt\x64" *> "$r\temp\_h393_${name}_link.txt"
if ($LASTEXITCODE) { Get-Content "$r\temp\_h393_${name}_link.txt" -Encoding Unicode; exit 1 }
$runner = "$r\temp\_h393_$name.inner.ps1"
& $r\QwenKernPremium\build\$name.exe --pid 14008 *> "$r\temp\_h393_${name}_run.txt"
$LASTEXITCODE | Set-Content "$r\temp\_h393_${name}_rc.txt"
exit $LASTEXITCODE