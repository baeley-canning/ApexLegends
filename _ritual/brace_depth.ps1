# ============================================================================
# _ritual\brace_depth.ps1 — READ-ONLY brace/scope probe for a C++ source file.
#
# Why: the overlay rewrite stopped compiling with C1075 (no matching '{') plus
# "identifier not found" cascades, which is the signature of an unbalanced
# brace deep inside a namespace.  This walks the file character by character
# (string literals, char literals, // and /* */ comments skipped), tracks the
# depth, and prints the depth at caller-chosen line numbers so the exact line
# that opens an extra scope is visible without compiling.
#
# Mutates nothing.  Usage:
#   powershell -ExecutionPolicy Bypass -File _ritual\brace_depth.ps1 `
#       -Path <file.cpp> [-Mark 531,965,1372,...]
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Path,
    [int[]] $Mark = @()
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path)) { throw "missing file: $Path" }

$lines  = [IO.File]::ReadAllLines($Path)
$depth  = 0
$inBlock = $false
$report = New-Object System.Collections.ArrayList
$decls  = New-Object System.Collections.ArrayList

for ($i = 0; $i -lt $lines.Length; $i++) {
    $lineNo = $i + 1
    $line   = $lines[$i]
    $open   = 0
    $close  = 0
    $c      = 0
    while ($c -lt $line.Length) {
        $ch = $line[$c]
        $nx = if ($c + 1 -lt $line.Length) { $line[$c + 1] } else { [char]0 }

        if ($inBlock) {
            if ($ch -eq '*' -and $nx -eq '/') { $inBlock = $false; $c += 2; continue }
            $c++
            continue
        }
        if ($ch -eq '/' -and $nx -eq '*') { $inBlock = $true; $c += 2; continue }
        if ($ch -eq '/' -and $nx -eq '/') { break }

        if ($ch -eq '"') {                       # string literal
            $c++
            while ($c -lt $line.Length) {
                if ($line[$c] -eq '\') { $c += 2; continue }
                if ($line[$c] -eq '"')  { $c++; break }
                $c++
            }
            continue
        }
        if ($ch -eq "'") {                       # char literal
            $c++
            while ($c -lt $line.Length) {
                if ($line[$c] -eq '\') { $c += 2; continue }
                if ($line[$c] -eq "'")  { $c++; break }
                $c++
            }
            continue
        }

        if ($ch -eq '{') { $open++ }
        elseif ($ch -eq '}') { $close++ }
        $c++
    }

    $beforeDepth = $depth
    $depth += $open
    $depth -= $close

    $interesting = ($depth -lt 0) -or ($Mark -contains $lineNo) -or
                   ($line -match '^\s*(namespace|\} *// *namespace)')
    if ($interesting) {
        [void]$report.Add(('{0,6}  before {1,3} -> after {2,3}  {3}' -f $lineNo, $beforeDepth, $depth, $line.Trim()))
    }
    if ($depth -lt 0) { Write-Host "NEGATIVE depth at line $lineNo - extra '}'" }

    # Column-0 declarations: inside the one unnamed namespace these all start at
    # depth 1.  A run of them starting at depth >= 2 means an earlier function
    # body was never closed and swallowed the rest of the file.
    if ($line -match '^[A-Za-z_].*[\)\]]\s*(const\s*)?$' -or
        $line -match '^[A-Za-z_][A-Za-z0-9_:<>,\* ]*\s+[A-Za-z_][A-Za-z0-9_]*\s*\(' ) {
        [void]$decls.Add(('{0,6}  before {1,3} -> after {2,3}  {3}' -f $lineNo, $beforeDepth, $depth, $line.Trim()))
    }
}

Write-Host "file      : $Path"
Write-Host "lines     : $($lines.Length)"
Write-Host "final depth: $depth   (0 = balanced, >0 = missing '}' , <0 = extra '}')"
Write-Host "--- scope trace (namespaces + marked lines + anomalies) ---"
$report | ForEach-Object { Write-Host $_ }
Write-Host "--- column-0 declarations (expected depth 1 inside the unnamed namespace) ---"
$decls | ForEach-Object { Write-Host $_ }
if ($depth -ne 0) { exit 1 }
exit 0
