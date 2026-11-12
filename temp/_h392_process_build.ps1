$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$c = 'C:\BuildTools\VC\Tools\MSVC\14.44.35207'
$k = 'C:\Program Files (x86)\Windows Kits\10'
$v = '10.0.26100.0'
& "$c\bin\Hostx64\x64\cl.exe" /nologo /c /W4 /EHsc /MT /O2 /D_WIN32_WINNT=0x0A00 `
  "/Fo$r\QwenKernPremium\build\obj\qk_process_query.obj" "/I$c\include" `
  "/I$k\Include\$v\um" "/I$k\Include\$v\shared" "/I$k\Include\$v\ucrt" `
  "$r\QwenKernPremium\tools\qk_process_query.cpp" *> "$r\temp\_h392_process_build.txt"
if ($LASTEXITCODE) { Get-Content "$r\temp\_h392_process_build.txt" -Encoding Unicode; exit 1 }
& "$c\bin\Hostx64\x64\link.exe" /nologo /MACHINE:X64 /SUBSYSTEM:CONSOLE /INCREMENTAL:NO `
  "/OUT:$r\QwenKernPremium\build\qk_process_query.exe" `
  "$r\QwenKernPremium\build\obj\qk_process_query.obj" kernel32.lib ntdll.lib `
  "/LIBPATH:$c\lib\x64" "/LIBPATH:$k\Lib\$v\um\x64" "/LIBPATH:$k\Lib\$v\ucrt\x64" `
  *> "$r\temp\_h392_process_link.txt"
if ($LASTEXITCODE) { Get-Content "$r\temp\_h392_process_link.txt" -Encoding Unicode; exit 1 }
Write-Output BUILD_OK