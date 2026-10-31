# ============================================================================
# tools\BuildDriver.ps1 — build apexdrv.sys with the INSTALLED WDK.
#
# Why not msbuild driver\apexdrv.vcxproj:
#   The WDK kit is installed (Windows Kits\10\Include\10.0.26100.0\km,
#   Lib\...\km\x64, build\10.0.26100.0) but the Visual Studio *toolset*
#   registration ("WindowsKernelModeDriver10.0") is not, so MSBuild stops with
#   error MSB8020 before compiling anything.  Adding the VS component
#   "Windows Driver Kit" fixes that; until then this script compiles with the
#   same cl.exe/link.exe the toolset would use, with the same include/lib layout
#   (km + km\crt + shared + um, exactly like WindowsDriver.KernelMode.props).
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\BuildDriver.ps1
# Output: build\apexdrv.sys (x64, NATIVE subsystem, ntoskrnl.exe import)
# ============================================================================
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')] [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$BuildDir  = Join-Path $RepoRoot 'build'
$ObjDir    = Join-Path $BuildDir "obj\apexdrv\$Configuration"
$Log       = Join-Path $BuildDir 'driver_build.log'
$Source    = Join-Path $RepoRoot 'driver\apexdrv.c'
$Output    = Join-Path $BuildDir 'apexdrv.sys'
$Object    = Join-Path $ObjDir 'apexdrv.obj'

New-Item -ItemType Directory -Force -Path $ObjDir | Out-Null

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
                  Where-Object { Test-Path (Join-Path $_.FullName 'km') } |
                  Sort-Object Name)
    if ($versions.Count -eq 0) { return $null }
    return $versions[-1].Name
}

$cl     = Find-MsvcTool 'cl.exe'
$link   = Find-MsvcTool 'link.exe'
$kit    = Find-KitVersion
if (-not $cl -or -not $link) { throw 'MSVC cl.exe/link.exe not found (BuildTools VC tools missing)' }
if (-not $kit)               { throw 'WDK km headers not found (install Microsoft.WindowsWDK.*)' }

$IncRoot = 'C:\Program Files (x86)\Windows Kits\10\Include'
$LibRoot = 'C:\Program Files (x86)\Windows Kits\10\Lib'
$kmInc   = Join-Path $IncRoot "$kit\km"
$kmLib   = Join-Path $LibRoot "$kit\km\x64"

"=== DRIVER BUILD - $Configuration|x64 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" |
    Set-Content -Encoding utf8 $Log
"cl      : $cl"   | Add-Content -Encoding utf8 $Log
"link    : $link" | Add-Content -Encoding utf8 $Log
"kit     : $kit"  | Add-Content -Encoding utf8 $Log

# /kernel        : kernel codegen (implies /GS- etc.)
# /Zl            : do not embed a default CRT library name (we link kernel libs)
# /external:*    : keep WDK header noise out of OUR warning budget
$compileArgs = @(
    '/nologo', '/c', "/Fo$Object",
    '/W4', '/GS-', '/kernel', '/Zl', '/O2', '/DNDEBUG',
    '/D_AMD64_', '/DAMD64', '/D_WIN64', '/DPOOL_NX_OPTIN=1', '/D_WIN32_WINNT=0x0A00',
    "/I$kmInc", "/I$(Join-Path $IncRoot "$kit\km\crt")",
    "/I$(Join-Path $IncRoot "$kit\shared")", "/I$(Join-Path $IncRoot "$kit\um")",
    "/external:I$kmInc", "/external:I$(Join-Path $IncRoot "$kit\shared")",
    "/external:W0",
    "/I$(Join-Path $RepoRoot 'include')",
    $Source
)

& $cl @compileArgs *>> $Log
$compileExit = $LASTEXITCODE
"CL_EXIT=$compileExit" | Add-Content -Encoding utf8 $Log
if ($compileExit -ne 0) {
    Get-Content $Log -Tail 40 | Write-Host
    throw "driver compile failed (CL_EXIT=$compileExit); see $Log"
}

# Kernel libs only: ntoskrnl + hal + wdm (I/O manager support) + the two
# static CRT helpers (BufferOverflowK for safe-* / libcntpr for wcslen etc.).
$linkArgs = @(
    '/nologo', '/DRIVER', '/SUBSYSTEM:NATIVE', '/MACHINE:X64',
    '/ENTRY:DriverEntry', "/OUT:$Output", '/NODEFAULTLIB',
    "/LIBPATH:$kmLib",
    $Object, 'ntoskrnl.lib', 'hal.lib', 'wdm.lib', 'BufferOverflowK.lib', 'libcntpr.lib'
)

& $link @linkArgs *>> $Log
$linkExit = $LASTEXITCODE
"LINK_EXIT=$linkExit" | Add-Content -Encoding utf8 $Log
if ($linkExit -ne 0) {
    Get-Content $Log -Tail 40 | Write-Host
    throw "driver link failed (LINK_EXIT=$linkExit); see $Log"
}

$warnings = @(Select-String -Path $Log -Pattern ': warning ' -ErrorAction SilentlyContinue)
"warnings: $($warnings.Count)" | Add-Content -Encoding utf8 $Log
$warnings | Select-Object -First 10 | ForEach-Object { "  $($_.Line.Trim())" | Add-Content -Encoding utf8 $Log }

$artifact = Get-Item $Output
"artifact: $($artifact.FullName) ($($artifact.Length) bytes)" | Add-Content -Encoding utf8 $Log
Write-Host "DRIVER BUILD OK: $Output ($($artifact.Length) bytes, $($warnings.Count) warning(s))"
exit 0
