# ============================================================================
# tools\BuildOverlayTest.ps1 — PHASE 1 / T1: build build\overlay_test.exe.
#
# Compiles the REAL overlay (src\d3d12_overlay.cpp) together with the
# standalone test target (src\overlay_test.cpp) and the payload sources it
# shares (features / config / log / memory).  NOT part of apex_cheat.vcxproj —
# this exe deliberately links d3d12.lib/dxgi.lib directly (the KERNEL32+USER32
# IAT constraint applies to the payload DLL, not the offline test exe).
#
# cl.exe cannot parse the 'New User' repo path through cmd wrappers, so — like
# tools\BuildDriver.ps1 — everything goes through PowerShell & invocation with
# argument arrays (each element quoted exactly once by the engine).  Tool output
# is captured through a merged-stream expression and appended to the log with
# .NET file APIs so the log stays UTF-8 end to end.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\BuildOverlayTest.ps1
# Output: build\overlay_test.exe, log build\overlay_test_build.log
# ============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot 'build'
$ObjDir   = Join-Path $BuildDir 'obj\overlay_test'
$Log      = Join-Path $BuildDir 'overlay_test_build.log'
$Output   = Join-Path $BuildDir 'overlay_test.exe'

[void][IO.Directory]::CreateDirectory($ObjDir)

function Find-MsvcTool([string] $name) {
    $root = 'C:\BuildTools\VC\Tools\MSVC'
    if (-not (Test-Path $root)) { $root = Join-Path $env:ProgramFiles 'Microsoft Visual Studio' }
    $hits = @(Get-ChildItem $root -Recurse -Filter $name -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -match 'Hostx64\\x64' } |
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
if (-not $kit)               { throw 'Windows SDK um headers not found (d3d12.h etc.)' }

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

function Log([string] $line) {
    [IO.File]::AppendAllText($Log, $line + "`r`n")
}

function Invoke-Tool([string] $exe, [string[]] $argv, [string] $what) {
    # Native tool with merged streams, captured as a string (token replaced at
    # generation time so the generator command stays redirect-free).
    $ErrorActionPreference = 'Continue'
    $text = (& $exe @argv 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Log ("--- $what exit=$code")
    if ($text) { Log $text.TrimEnd() }
    return $code
}

[IO.File]::WriteAllText($Log, "=== OVERLAY TEST BUILD - " +
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===`r`n")
Log "cl      : $cl"
Log "link    : $link"
Log "kit     : $kit"
Log "msvcInc : $msvcInc"

# The repo's own headers stay /W4-internal; SDK + STL headers are external
# (/external:W0) so their noise is not our warning budget.
$sources = @(
    (Join-Path $RepoRoot 'src\overlay_test.cpp'),
    (Join-Path $RepoRoot 'src\d3d12_overlay.cpp'),
    (Join-Path $RepoRoot 'src\features.cpp'),
    (Join-Path $RepoRoot 'src\config.cpp'),
    (Join-Path $RepoRoot 'src\log.cpp'),
    (Join-Path $RepoRoot 'src\memory.cpp')
)

$objs = @()
foreach ($src in $sources) {
    if (-not (Test-Path $src)) { throw "source missing: $src" }
    $obj  = Join-Path $ObjDir ([IO.Path]::GetFileNameWithoutExtension($src) + '.obj')
    $objs += $obj

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
    ) "cl $([IO.Path]::GetFileName($src))"
    if ($code -ne 0) {
        throw "compile failed: $src (exit=$code, see $Log)"
    }
}
Log "CL_EXIT=0 (all $($sources.Count) translation units)"

# d3d12/dxgi are linked HERE ONLY (test exe); the payload DLL resolves the
# same DLLs with LoadLibrary/GetProcAddress and stays KERNEL32+USER32.
$linkArgs = @(
    '/nologo', '/MACHINE:X64', "/OUT:$Output", '/SUBSYSTEM:WINDOWS',
    '/INCREMENTAL:NO', '/ENTRY:wWinMainCRTStartup'
) + $objs + @(
    'kernel32.lib', 'user32.lib', 'gdi32.lib', 'd3d12.lib', 'dxgi.lib',
    'psapi.lib',
    "/LIBPATH:$umLib", "/LIBPATH:$ucrtLib", "/LIBPATH:$msvcLib"
)

$linkExit = Invoke-Tool $link $linkArgs 'link'
Log "LINK_EXIT=$linkExit"
if ($linkExit -ne 0) {
    throw "link failed (LINK_EXIT=$linkExit); see $Log"
}

$warnings = @(Select-String -Path $Log -Pattern ': warning ' -ErrorAction SilentlyContinue)
Log "warnings: $($warnings.Count)"
$warnings | Select-Object -First 10 | ForEach-Object {
    Log ("  " + $_.Line.Trim()) }

$artifact = Get-Item $Output
Log "artifact: $($artifact.FullName) ($($artifact.Length) bytes)"
Write-Host "OVERLAY TEST BUILD OK: $Output ($($artifact.Length) bytes, $($warnings.Count) warning(s))"
exit 0