# _psctest.ps1 - non-elevated proof that New-FileCatalog -CatalogVersion 2 is the SHA-256 catalog
# generator ci.dll wants, and that its member name is the CryptCATAdmin ENGINE hash (drop -Checksum /
# cert-table), not a plain file hash.  No admin needed: the cat is inspected byte-wise here.
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$out = Join-Path $d '_psctest.txt'
function L($m) { Add-Content -Encoding utf8 $out $m }
Set-Content -LiteralPath $out -Value ('psctest ' + (Get-Date)) -Encoding utf8

$have = [bool](Get-Command New-FileCatalog -ErrorAction SilentlyContinue)
L ('New-FileCatalog available = ' + $have)
if (-not $have) { L 'END-psctest'; exit }

$t = Join-Path $d '_psctest'
Remove-Item -LiteralPath $t -Recurse -Force -EA SilentlyContinue
$src = Join-Path $t 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
Set-Content -LiteralPath (Join-Path $src 'p26probe.bin') -Value ('psctest probe ' + [Guid]::NewGuid()) -Encoding ascii
$drv = Join-Path (Split-Path -Parent $d) 'QwenKernPremium\build\apexdrv.sys'
if (Test-Path -LiteralPath $drv) { Copy-Item -LiteralPath $drv -Destination (Join-Path $src 'apexdrv_build.sys') -Force; L ('added signed driver: ' + $drv) }
else { L ('WARN signed driver not found: ' + $drv) }

$cat = Join-Path $t 'psc.cat'
New-FileCatalog -Path $src -CatalogFilePath $cat -CatalogVersion 2 -ErrorAction SilentlyContinue -Verbose 4>&1 |
    ForEach-Object { L ('  verbose: ' + $_) }
if (-not (Test-Path -LiteralPath $cat)) { L 'no .cat produced'; L 'END-psctest'; exit }
L ('cat len = ' + (Get-Item $cat).Length)

# the cat is DER and member names are ASCII hex -> read the raw bytes as ASCII and search them
$bytes = [IO.File]::ReadAllBytes($cat)
$txt = -join ($bytes | ForEach-Object { if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { '.' } })
$cl = Join-Path $d 'cateng.ps1'
foreach ($f in (Get-ChildItem -LiteralPath $src -File)) {
    $plain  = (Get-FileHash -Algorithm sha256 -LiteralPath $f.FullName).Hash
    $plain1 = (Get-FileHash -Algorithm sha1   -LiteralPath $f.FullName).Hash
    $eng = ''
    & $cl -Path $f.FullName -Alg sha256 -NoApi 2>&1 | Out-Null
    try {
        foreach ($ln in (Get-Content -LiteralPath (Join-Path $d 'cateng.txt') -Tail 8)) {
            $mm = [regex]::Match($ln, '^\s*sha256\s+engine=([0-9A-F]{64})'); if ($mm.Success) { $eng = $mm.Groups[1].Value }
        }
    } catch { }
    L ('  file=' + $f.Name + ' len=' + $f.Length)
    L ('    engine sha256 present in cat = ' + [bool]($txt -match $eng) + '   engine=' + $eng)
    L ('    plain  sha256 present in cat = ' + [bool]($txt -match $plain))
    L ('    plain  sha1   present in cat = ' + [bool]($txt -match $plain1))
}
$n64 = ([regex]::Matches($txt, '(?i)[0-9a-f]{64}')).Count
$n40 = ([regex]::Matches($txt, '(?i)[0-9a-f]{40}')).Count
L ('  hex tokens in cat: 64-char=' + $n64 + '  40-char=' + $n40)
L 'END-psctest'
