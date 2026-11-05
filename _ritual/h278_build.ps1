# ============================================================================
# _ritual\h278_build.ps1 — build the 1 KB control payload for the delivery split.
#
# Why not msbuild: the same reason BuildDriver.ps1 gives (no VS toolset
# registration for driver projects), and a 60-line DLL does not need a project.
# Same cl.exe discovery, same "never call cl from a directory with a space in it"
# rule: sources and objects live under _ritual\apxprobe, the artifact is written
# STRAIGHT into the space-free payload share C:\p37vm\payload so the guest path
# matches the apexcheat.dll arm exactly.
#
# Usage:  powershell -ExecutionPolicy Bypass -File _ritual\h278_build.ps1
# Output: C:\p37vm\payload\apxprobe.dll
# ============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source   = Join-Path $RepoRoot '_ritual\apxprobe\apxprobe.c'
$Object   = Join-Path $RepoRoot '_ritual\apxprobe\apxprobe.obj'
$Payload  = 'C:\p37vm\payload'
$Output   = Join-Path $Payload 'apxprobe.dll'
$Log      = Join-Path $RepoRoot '_ritual\h278_build.log'

if (-not (Test-Path $Payload)) { throw "payload share not present: $Payload" }

function Find-MsvcTool([string] $name) {
    $root = 'C:\BuildTools\VC\Tools\MSVC'
    if (-not (Test-Path $root)) { $root = Join-Path $env:ProgramFiles 'Microsoft Visual Studio' }
    $hits = @(Get-ChildItem $root -Recurse -Filter $name -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -match 'Hostx64\\x64' } |
              Sort-Object FullName)
    if ($hits.Count -eq 0) { return $null }
    return $hits[-1].FullName
}

$cl = Find-MsvcTool 'cl.exe'
if (-not $cl) { throw 'cl.exe not found' }

"=== h278 payload build - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Encoding utf8 $Log
"cl      : $cl" | Add-Content -Encoding utf8 $Log
"source  : $Source" | Add-Content -Encoding utf8 $Log

# /LD DLL, /MT- CRT (static-free), /O2, /W4.  /NODEFAULTLIB keeps the import
# table empty; the linker still emits KERNEL32 only if something forces it.
# Windows headers therefore come from the UM kit.
$kit = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Include' -Directory -ErrorAction Stop |
       Where-Object { Test-Path (Join-Path $_.FullName 'um') } |
       Sort-Object Name | Select-Object -Last 1
$umInc = Join-Path $kit.FullName 'um'
$sharedInc = Join-Path $kit.FullName 'shared'
# windows.h pulls excpt.h/string.h from the CRT and ucrt headers even when no CRT
# is linked, so both include roots are needed as well.
$crtInc = Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $cl)))) 'include'
$ucrtInc = Join-Path $kit.FullName 'ucrt'
$umLib = Join-Path (Join-Path 'C:\Program Files (x86)\Windows Kits\10\Lib' $kit.Name) 'um\x64'

$compileArgs = @(
    '/nologo', '/c', '/LD', '/O2', '/W4', '/GS-', '/Zl', '/DNDEBUG',
    '/D_AMD64_', '/DAMD64', '/D_WIN64', "/Fo$Object",
    "/I$crtInc", "/I$ucrtInc", "/I$umInc", "/I$sharedInc",
    "/external:I$umInc", "/external:I$sharedInc", "/external:W0",
    $Source
)

& $cl @compileArgs *>> $Log
if ($LASTEXITCODE -ne 0) { Get-Content $Log -Tail 40 | Write-Host; throw "compile failed; see $Log" }

& $cl '/nologo', '/LD', "/Fe$Output", $Object, '/link', '/NODEFAULTLIB',
       '/MACHINE:X64', '/SUBSYSTEM:WINDOWS', '/ENTRY:DllMain',
       "/LIBPATH:$umLib", 'kernel32.lib' *>> $Log
if ($LASTEXITCODE -ne 0) { Get-Content $Log -Tail 40 | Write-Host; throw "link failed; see $Log" }

$warnings = @(Select-String -Path $Log -Pattern ': warning ' -ErrorAction SilentlyContinue)
$artifact = Get-Item $Output
"artifact: $($artifact.FullName) ($($artifact.Length) bytes) warnings=$($warnings.Count)" |
    Add-Content -Encoding utf8 $Log
Write-Host "PAYLOAD BUILD OK: $Output ($($artifact.Length) bytes, $($warnings.Count) warning(s))"
exit 0
