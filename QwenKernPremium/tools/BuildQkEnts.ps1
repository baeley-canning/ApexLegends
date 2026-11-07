# ============================================================================
# tools\BuildQkProbe.ps1 - build build\qk_ents.exe (PLAN stage 1 bridge probe).
#
# One translation unit, console subsystem, links kernel32 only.  Same toolchain
# discovery and the same "cl.exe cannot parse 'New User'" workaround as
# BuildOverlayTest.ps1 / BuildDriver.ps1: PowerShell & invocation with argument
# arrays, every element quoted exactly once by the engine.
#
# Usage:  powershell -ExecutionPolicy Bypass -File QwenKernPremium\tools\BuildQkProbe.ps1
# Output: QwenKernPremium\build\qk_ents.exe, log build\qk_ents_build.log
# ============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot 'build'
$ObjDir   = Join-Path $BuildDir 'obj\qk_ents'
$Log      = Join-Path $BuildDir 'qk_ents_build.log'
$Output   = Join-Path $BuildDir 'qk_ents.exe'

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

[IO.File]::WriteAllText($Log, "=== qk_ents BUILD - " +
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===`r`n")
Log "cl      : $cl"
Log "link    : $link"
Log "kit     : $kit"

$src = Join-Path $RepoRoot 'tools\qk_ents.cpp'
if (-not (Test-Path $src)) { throw "source missing: $src" }
$obj = Join-Path $ObjDir 'qk_ents.obj'

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
) 'cl qk_ents.cpp'
if ($code -ne 0) { throw "compile failed (exit=$code, see $Log)" }

$linkArgs = @(
    '/nologo', '/MACHINE:X64', "/OUT:$Output", '/SUBSYSTEM:CONSOLE',
    '/INCREMENTAL:NO', $obj,
    'kernel32.lib', 'user32.lib',
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
Write-Host "qk_ents BUILD OK: $Output ($($artifact.Length) bytes, $($warnings.Count) warning(s))"
exit 0

