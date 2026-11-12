$r='C:\Users\New User\OneDrive\Desktop\cheating'
$c='C:\BuildTools\VC\Tools\MSVC\14.44.35207'
$k='C:\Program Files (x86)\Windows Kits\10'
$v='10.0.26100.0'
& "$c\bin\Hostx64\x64\cl.exe" /nologo /c /EHsc /MT /O2 /D_WIN32_WINNT=0x0A00 `
 "/Fo$r\QwenKernPremium\build\obj\qk_self_extension.obj" "/I$c\include" `
 "/I$k\Include\$v\um" "/I$k\Include\$v\shared" "/I$k\Include\$v\ucrt" `
 "$r\QwenKernPremium\tools\qk_self_extension.cpp" *> "$r\temp\h399_self_build.txt"
if($LASTEXITCODE){Get-Content "$r\temp\h399_self_build.txt" -Encoding Unicode;exit 1}
& "$c\bin\Hostx64\x64\link.exe" /nologo /MACHINE:X64 /SUBSYSTEM:CONSOLE `
 "/OUT:$r\QwenKernPremium\build\qk_self_extension.exe" "$r\QwenKernPremium\build\obj\qk_self_extension.obj" `
 kernel32.lib ntdll.lib "/LIBPATH:$c\lib\x64" "/LIBPATH:$k\Lib\$v\um\x64" `
 "/LIBPATH:$k\Lib\$v\ucrt\x64" *> "$r\temp\h399_self_link.txt"
if($LASTEXITCODE){Get-Content "$r\temp\h399_self_link.txt" -Encoding Unicode;exit 1}
$s=Join-Path $r 'temp\h399_self_inner.ps1'
"& '$r\QwenKernPremium\build\qk_self_extension.exe' *> '$r\temp\h399_self.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru