& "$c\bin\Hostx64\x64\cl.exe" /nologo /c /EHsc /MT /O2 /W4 /D_WIN32_WINNT=0x0A00 `
 "/Fo$r\QwenKernPremium\build\obj\qk_player_probe.obj" "/I$c\include" `
 "/I$k\Include\$v\um" "/I$k\Include\$v\shared" "/I$k\Include\$v\ucrt" `
 "$r\QwenKernPremium\tools\qk_player_probe.cpp" *> "$r\temp\h411_body_probe_build.txt"
if($LASTEXITCODE){Get-Content "$r\temp\h411_body_probe_build.txt" -Encoding Unicode;exit 1}

$r='C:\Users\New User\OneDrive\Desktop\cheating'
$c='C:\BuildTools\VC\Tools\MSVC\14.44.35207'
$k='C:\Program Files (x86)\Windows Kits\10'
$v='10.0.26100.0'
& "$c\bin\Hostx64\x64\cl.exe" /nologo /c /EHsc /MT /O2 /W4 /D_WIN32_WINNT=0x0A00 `
 "/Fo$r\QwenKernPremium\build\obj\qk_userread.obj" "/I$c\include" `
 "/I$k\Include\$v\um" "/I$k\Include\$v\shared" "/I$k\Include\$v\ucrt" `
 "$r\QwenKernPremium\tools\qk_userread.cpp" *> "$r\temp\h411_body_build.txt"
if($LASTEXITCODE){Get-Content "$r\temp\h411_body_build.txt" -Encoding Unicode;exit 1}
& "$c\bin\Hostx64\x64\link.exe" /nologo /MACHINE:X64 /SUBSYSTEM:CONSOLE `
 "/OUT:$r\QwenKernPremium\build\qk_player_probe.exe" "$r\QwenKernPremium\build\obj\qk_player_probe.obj" `
 "$r\QwenKernPremium\build\obj\qk_userread.obj" kernel32.lib ntdll.lib advapi32.lib `
 "/LIBPATH:$c\lib\x64" "/LIBPATH:$k\Lib\$v\um\x64" "/LIBPATH:$k\Lib\$v\ucrt\x64" *> "$r\temp\h411_body_link.txt"
if($LASTEXITCODE){Get-Content "$r\temp\h411_body_link.txt" -Encoding Unicode;exit 1}
$s=Join-Path $r 'temp\h411_body_inner.ps1'
"& '$r\QwenKernPremium\build\qk_player_probe.exe' '--pid','14624' *> '$r\temp\h411_body.txt'"|Set-Content $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
Get-Content "$r\temp\h411_body.txt" -Tail 80 -ErrorAction SilentlyContinue | Out-String | Write-Output