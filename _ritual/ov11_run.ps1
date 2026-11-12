# ============================================================================
# _ritual\ov11_run.ps1 - T6 geometry probe run (new number, R5).
#
# What changed vs ov7/ov10: the test target now (a) is DPI aware, (b) shows the
# window BEFORE creating the flip-model chain (a hidden window makes Present take
# the occluded fast path and DWM never composites the buffer - that was the white
# client), (c) reads the LIVE client rect and sizes chain/viewport/background
# from it, and (d) measures the drawn buffer through a readback and FAILS under
# 80 % coverage.  So this run has to be judged on ov11_result.txt numbers first,
# screenshots second.
#
# Evidence: ov11_run.out, ov11_test.png, ov11_desk.png, ov11_buffer.bmp,
# ov11_ocr.txt.  No kernel state involved.
# ============================================================================
param([int] $Seconds = 40, [int] $ShotAt = 6)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\overlay_test.exe'
$cwd  = Join-Path $rit  'ov11_cwd'
$utf8 = [Text.UTF8Encoding]::new($false)

if (-not (Test-Path $exe)) { throw "overlay_test.exe missing: $exe" }
[void][IO.Directory]::CreateDirectory($cwd)
foreach ($f in [IO.Directory]::GetFiles($cwd)) { [IO.File]::Delete($f) }

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$proc = Start-Process -FilePath $exe `
    -ArgumentList @("--seconds $Seconds", "--outdir `"$cwd`"") `
    -WorkingDirectory $cwd -PassThru
Start-Sleep -Seconds $ShotAt

$shotTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'shot_win.ps1') -Title 'QwenKern Overlay Test' `
    -Out (Join-Path $rit 'ov11_test.png')) -join "`r`n"
$deskTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'shot_desk.ps1')) -join "`r`n"
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') `
    -Destination (Join-Path $rit 'ov11_desk.png') -Force

$ocrTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'ocr.ps1') -Path (Join-Path $rit 'ov11_test.png') `
    -Out (Join-Path $rit 'ov11_ocr.txt')) -join "`r`n"

$proc.WaitForExit()
$exitCode = $proc.ExitCode

$resultTxt = '(missing)'
$rp = Join-Path $cwd 'ov_test_result.txt'
if (Test-Path $rp) { $resultTxt = [IO.File]::ReadAllText($rp) }
$bufTxt = '(no buffer dump)'
$bp = Join-Path $cwd 'ov_buffer.bmp'
if (Test-Path $bp) {
    Copy-Item -LiteralPath $bp -Destination (Join-Path $rit 'ov11_buffer.bmp') -Force
    $bufTxt = 'ov_buffer.bmp -> _ritual\ov11_buffer.bmp (' + (Get-Item $bp).Length + ' bytes)'
}
$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\overlay_test_$($proc.Id).log"
$logTxt = '(missing)'
if (Test-Path $logPath) { $logTxt = [IO.File]::ReadAllText($logPath) }

$out = "ov11 - T6 geometry probe (visible-window chain, live client rect, readback gate) - $stamp`r`n" +
       "exe   : $exe`r`n" +
       "cwd   : $cwd (scratch, emptied first)`r`n" +
       "pid   : $($proc.Id)   exit code: $exitCode  (0 = PASS, 2 = FAIL)`r`n" +
       "shot  : $shotTxt`r`n" +
       "desk  : $deskTxt`r`n" +
       "ocr   : $ocrTxt`r`n" +
       "buffer: $bufTxt`r`n" +
       "---- ov_test_result.txt ----`r`n" + $resultTxt + "`r`n" +
       "---- overlay_test log ----`r`n" + $logTxt + "`r`n"
[IO.File]::WriteAllText((Join-Path $rit 'ov11_run.out'), $out, $utf8)

Write-Host "OV11 DONE exit=$exitCode"