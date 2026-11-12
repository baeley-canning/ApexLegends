$ErrorActionPreference = 'Stop'
$outDir = 'C:\temp'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$root = 'C:\Users\New User\OneDrive\Desktop\cheating'

# Directories at depth 1
Get-ChildItem -Path $root -Recurse -Depth 1 -Directory |
    Select-Object -ExpandProperty FullName |
    Sort-Object |
    Out-File -FilePath (Join-Path $outDir 'topdirs.txt') -Encoding utf8

# Files at depth 0 (root)
Get-ChildItem -Path $root -Depth 0 -File |
    Select-Object -ExpandProperty Name |
    Sort-Object |
    Out-File -FilePath (Join-Path $outDir 'rootfiles.txt') -Encoding utf8

# Total file count and total dir count
$totalFiles = (Get-ChildItem -Path $root -Recurse -File).Count
$totalDirs  = (Get-ChildItem -Path $root -Recurse -Directory).Count
"TOTAL_FILES=$totalFiles" | Out-File -FilePath (Join-Path $outDir 'totals.txt') -Encoding utf8
"TOTAL_DIRS=$totalDirs" | Add-Content -FilePath (Join-Path $outDir 'totals.txt') -Encoding utf8

Write-Output "SCAN_DONE files=$totalFiles dirs=$totalDirs"
