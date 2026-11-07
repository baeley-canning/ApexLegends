# ============================================================================
# tools\BuildQkOverlay.ps1 - build build\qk_overlay.exe (standalone external
# overlay: layered window + GDI back buffer + named shared memory producer
# link).  Same shape as tools\BuildQkProbe.ps1.
#
# One translation unit, CONSOLE subsystem (the operator reads the OVERLAY:
# lines on stdout and in the log), links kernel32 + user32 + gdi32 only.
# The toolchain is discovered by path, not by vcvars, and every native tool is
# invoked with an argument array so PowerShell quotes each element exactly once
# (cl.exe cannot parse the 'New User' repo path through cmd wrappers).
#
# Usage:  powershell -ExecutionPolicy Bypass -File QwenKernPremium\tools\BuildQkOverlay.ps1
# Output: QwenKernPremium\build\qk_overlay.exe, log build\qk_overlay_build.log
# ============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot 'build'
$ObjDir   = Join-Path $BuildDir 'obj\qk_overlay'
$Log      = Join-Path $BuildDir 'qk_overlay_build.log'
$Output   = Join-Path $BuildDir 'qk_overlay.exe'

[void][IO.Directory]::CreateDirectory($ObjDir)

function Find-MsvcTool([string] $name) {
    $root = 'C:\BuildTools\VC\Tools\MSVC'
    if (-not (Test-Path $root)) { $root = Join-Path $env:ProgramFiles 'Microsoft Visual Studio' }
    $hits = @(Get-ChildItem $root -Recurse -Filter $name -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -like '*Hostx64\x64*' } |
              Sort-Object FullName)
    if ($hits.Count -eq 0) { return $null }
    return $hits[-1].FullName
}

function Find-KitVersion {
    $root = 'C:\Program Files (x86)\Windows Kits\10\Include'
    if (-not (Test-Path $root)) { return $null }
    $versions = @(Get-ChildItem $root -Directory |
                  Where-Object { Test-Path (Join-Path $_.FullName 'um') } |
                  Sort-Object Name)
    if ($versions.Count -eq 0) { return $null }
    return $versions[-1].Name
}

$cl   = Find-MsvcTool 'cl.exe'
$link = Find-MsvcTool 'link.exe'
$kit  = Find-KitVersion
if (-not $cl -or -not $link) { throw 'MSVC cl.exe/link.exe not found (BuildTools VC tools missing)' }
if (-not $kit)               { throw 'Windows SDK um headers not found' }

# cl.exe = <MSVC>\bin\Hostx64\x64\cl.exe  (4 dir levels above the file)
$msvcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $cl)))
$msvcInc  = Join-Path $msvcRoot 'include'
$msvcLib  = Join-Path $msvcRoot 'lib\x64'

$IncRoot   = 'C:\Program Files (x86)\Windows Kits\10\Include'
$LibRoot   = 'C:\Program Files (x86)\Windows Kits\10\Lib'
$umInc     = Join-Path $IncRoot "$kit\um"
$sharedInc = Join-Path $IncRoot "$kit\shared"
$ucrtInc   = Join-Path $IncRoot "$kit\ucrt"
$umLib     = Join-Path $LibRoot "$kit\um\x64"
$ucrtLib   = Join-Path $LibRoot "$kit\ucrt\x64"

function Log([string] $line) { [IO.File]::AppendAllText($Log, $line + "`r`n") }

function Invoke-Tool([string] $exe, [string[]] $argv, [string] $what) {
    $ErrorActionPreference = 'Continue'
    $text = (& $exe @argv 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Log ("--- $what exit=$code")
    if ($text) { Log $text.TrimEnd() }
    return $code
}

[IO.File]::WriteAllText($Log, "=== QK_OVERLAY BUILD - " +
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===`r`n")
Log "cl      : $cl"
Log "link    : $link"
Log "kit     : $kit"

$src = Join-Path $RepoRoot 'tools\qk_overlay.cpp'
if (-not (Test-Path $src)) { throw "source missing: $src" }
$obj = Join-Path $ObjDir 'qk_overlay.obj'

# SDK headers are external (/external:W0): a warning from windows.h is not our
# warning budget.  /W4 applies to qk_overlay.cpp itself; target is 0 warnings.
$code = Invoke-Tool $cl @(
    '/nologo', '/c', '/W4', '/O2', '/DNDEBUG', '/EHsc', '/MT',
    '/D_WIN32_WINNT=0x0A00', '/DUNICODE', '/D_UNICODE', '/D_CRT_SECURE_NO_WARNINGS',
    "/Fo$obj",
    "/I$(Join-Path $RepoRoot 'include')",
    "/I$msvcInc", "/I$umInc", "/I$sharedInc", "/I$ucrtInc",
    "/external:I$msvcInc", "/external:I$umInc",
    "/external:I$sharedInc", "/external:I$ucrtInc",
    '/external:W0',
    $src
) 'cl qk_overlay.cpp'
if ($code -ne 0) { throw "compile failed (exit=$code, see $Log)" }

# CONSOLE, not WINDOWS: the OVERLAY: lines are the evidence.
$linkArgs = @(
    '/nologo', '/MACHINE:X64', "/OUT:$Output", '/SUBSYSTEM:CONSOLE',
    '/INCREMENTAL:NO', $obj,
    'kernel32.lib', 'user32.lib', 'gdi32.lib',
    "/LIBPATH:$umLib", "/LIBPATH:$ucrtLib", "/LIBPATH:$msvcLib"
)
$linkExit = Invoke-Tool $link $linkArgs 'link'
Log "LINK_EXIT=$linkExit"
if ($linkExit -ne 0) { throw "link failed (LINK_EXIT=$linkExit); see $Log" }

$warnings = @(Select-String -Path $Log -Pattern ': warning ' -ErrorAction SilentlyContinue)
Log "warnings: $($warnings.Count)"
$warnings | Select-Object -First 10 | ForEach-Object { Log ("  " + $_.Line.Trim()) }

$artifact = Get-Item $Output
Log "artifact: $($artifact.FullName) ($($artifact.Length) bytes)"
Write-Host "QK_OVERLAY BUILD OK: $Output ($($artifact.Length) bytes, $($warnings.Count) warning(s))"
exit 0
