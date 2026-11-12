# ov59_capture.ps1 - R5 evidence run for the QwenKernPremium overlay menu.
#
# 1. one default run (capture state = VISUALS with GLOW selected)
# 2. one run per category (--menu-tab 0..4)
# 3. each run's ov_buffer.bmp and ov_test_result.txt are copied to a
#    per-run name so nothing is overwritten between runs.
#
# The --outdir value is quoted: unquoted, "New User" splits the path and the
# harness silently writes to C:\Users\New (that is what broke ov57).
$ErrorActionPreference = 'Stop'
$ritual = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$exe    = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\overlay_test.exe'
$cwd    = Join-Path $ritual 'ov59_cwd'
if (-not (Test-Path -LiteralPath $exe)) { throw "missing $exe" }
[void][IO.Directory]::CreateDirectory($cwd)

function Run-One([string]$tag, [int]$tab, [int]$seconds) {
    $argLine = '--outdir "' + $cwd + '" --seconds ' + $seconds
    if ($tab -ge 0) { $argLine += ' --menu-tab ' + $tab }

    $p = Start-Process -FilePath $exe -ArgumentList $argLine -WorkingDirectory $cwd -PassThru
    $null = $p.WaitForExit(180000)

    $res = Join-Path $cwd 'ov_test_result.txt'
    $bmp = Join-Path $cwd 'ov_buffer.bmp'
    $out = @("tag=$tag", "args=$argLine", "exit=$($p.ExitCode)")
    if (Test-Path -LiteralPath $res) {
        Copy-Item -LiteralPath $res -Destination (Join-Path $ritual "ov59_$tag`_result.txt") -Force
        $out += (Get-Content -LiteralPath $res | Where-Object {
                    $_ -match 'capture state|^RESULT|navOk=|T6 geometry gate|vertex buffer|T3 tab' })
    } else { $out += 'MISSING ov_test_result.txt' }
    if (Test-Path -LiteralPath $bmp) {
        Copy-Item -LiteralPath $bmp -Destination (Join-Path $ritual "ov59_$tag.bmp") -Force
        $out += ('bmp=' + (Get-Item -LiteralPath (Join-Path $ritual "ov59_$tag.bmp")).Length)
    } else { $out += 'MISSING ov_buffer.bmp' }
    return $out
}

$all = @()
$all += Run-One 'default'  -1 12
foreach ($t in 0..4) { $all += Run-One ("tab$t") $t 8; $all += '---' }
[IO.File]::WriteAllLines((Join-Path $ritual 'ov59_capture_summary.txt'), $all)
$all -join "`n"
