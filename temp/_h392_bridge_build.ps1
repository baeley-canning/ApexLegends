# h392: compile the external PEB/DTB query bridge. No driver changes.
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out = Join-Path $root 'QwenKernPremium\build\qk_stage0_bridge.exe'
$obj = Join-Path $root 'QwenKernPremium\build\obj\qk_stage0_bridge.obj'
$log = Join-Path $root 'temp\_h392_build.txt'
$cl = 'C:\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe'
$link = 'C:\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
$inc = 'C:\BuildTools\VC\Tools\MSVC\14.44.35207\include'
$mlib = 'C:\BuildTools\VC\Tools\MSVC\14.44.35207\lib\x64'
$kit = 'C:\Program Files (x86)\Windows Kits\10'
$kv = '10.0.26100.0'
[IO.Directory]::CreateDirectory((Split-Path $obj)) | Out-Null
& $cl /nologo /c /W4 /O2 /EHsc /MT /DNDEBUG /D_WIN32_WINNT=0x0A00 /DUNICODE /D_UNICODE `
  "/Fo$obj" "/I$inc" "/I$kit\Include\$kv\um" "/I$kit\Include\$kv\shared" "/I$kit\Include\$kv\ucrt" `
  "$root\QwenKernPremium\tools\qk_stage0_bridge.cpp" *> $log
if ($LASTEXITCODE -ne 0) { Get-Content $log; throw 'compile failed' }
$linkLog = Join-Path $root 'temp\_h392_link.txt'
& $link /nologo /MACHINE:X64 "/OUT:$out" /SUBSYSTEM:CONSOLE /INCREMENTAL:NO $obj `
  kernel32.lib ntdll.lib "/LIBPATH:$mlib" "/LIBPATH:$kit\Lib\$kv\um\x64" `
  "/LIBPATH:$kit\Lib\$kv\ucrt\x64" *> $linkLog
$code = $LASTEXITCODE
Write-Output (Get-Content $log -Encoding Unicode | Out-String)
Write-Output (Get-Content $linkLog -Encoding Unicode | Out-String)
if ($code -ne 0) { throw 'link failed' }
Write-Host "BUILD_OK $out"