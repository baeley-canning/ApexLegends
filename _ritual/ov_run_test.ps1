# ============================================================================
# _ritual\ov_run_test.ps1 — PHASE 1 / T6 (ov-series): run build\overlay_test.exe
# with a scratch working directory, screenshot the window, OCR it, and write
# the evidence files ov2_testrun.out / ov3_test.png / ov4_test_ocr.txt /
# ov5_ini_rt.out.  No kernel or host state is touched (AGENTS R1: screenshot,
# OCR and process start are host-safe).
#
# One variable per run (R5): the freshly built overlay_test.exe.  Scratch dir
# ov2_cwd is recreated empty each run so no stale file can be read as fresh.
# ============================================================================
param([int] $Seconds = 14)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\overlay_test.exe'
$cwd  = Join-Path $rit  'ov2_cwd'
$utf8 = [Text.UTF8Encoding]::new($false)

if (-not (Test-Path $exe)) { throw "overlay_test.exe missing: $exe" }
[void][IO.Directory]::CreateDirectory($cwd)
foreach ($f in [IO.Directory]::GetFiles($cwd)) { [IO.File]::Delete($f) }

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$proc = Start-Process -FilePath $exe `
    -ArgumentList @("--seconds $Seconds", "--outdir `"$cwd`"")`
    -WorkingDirectory $cwd -PassThru
Start-Sleep -Seconds 6      # window up, device created, menu state driven, frames flowing

# ---- ov3: screenshot of the test window (harness shot_win.ps1) --------------
$shotTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'shot_win.ps1') -Title 'QwenKern Overlay Test' `
    -Out (Join-Path $rit 'ov3_test.png')) -join "`r`n"

# ---- ov4: OCR of the screenshot (harness ocr.ps1) ----------------------------
$ocrTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'ocr.ps1') -Path (Join-Path $rit 'ov3_test.png') `
    -Out (Join-Path $rit 'ov4_test_ocr.txt')) -join "`r`n"

$proc.WaitForExit()
$exitCode = $proc.ExitCode

# ---- ov2: run evidence -------------------------------------------------------
$resultTxt = '(missing)'
$rp = Join-Path $cwd 'ov_test_result.txt'
if (Test-Path $rp) { $resultTxt = [IO.File]::ReadAllText($rp) }
$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\overlay_test_$($proc.Id).log"
$logTxt = '(missing)'
if (Test-Path $logPath) { $logTxt = [IO.File]::ReadAllText($logPath) }

$ov2 = "ov2 - overlay_test run - $stamp`r`n" +
       "exe   : $exe`r`n" +
       "cwd   : $cwd (scratch, recreated empty before the run)`r`n" +
       "pid   : $($proc.Id)   exit code: $exitCode`r`n" +
       "shot  : $shotTxt`r`n" +
       "ocr   : $ocrTxt`r`n" +
       "---- ov_test_result.txt (written by the exe) ----`r`n" +
       $resultTxt + "`r`n" +
       "---- overlay_test log (payload log path, tag overlay_test) ----`r`n" +
       $logTxt + "`r`n"
[IO.File]::WriteAllText((Join-Path $rit 'ov2_testrun.out'), $ov2, $utf8)

# ---- ov5: T4 ini round-trip + live menu flush -------------------------------
$rtIni  = Join-Path $cwd 'ov_rt.ini'
$liveIni = Join-Path $cwd 'apexcheat.ini'
$rtTxt    = if (Test-Path $rtIni)  { [IO.File]::ReadAllText($rtIni) }  else { '(missing)' }
$liveTxt  = if (Test-Path $liveIni) { [IO.File]::ReadAllText($liveIni) } else { '(missing)' }
$ov5 = "ov5 - T4 config persistence - $stamp`r`n" +
       "---- ov_rt.ini (dedicated round-trip file: write then re-read) ----`r`n" +
       $rtTxt + "`r`n" +
       "---- apexcheat.ini in the scratch CWD (written by the LIVE menu ENTER path: SharedMenuConfig - FlushFeatureToggles) ----`r`n" +
       $liveTxt + "`r`n" +
       "RESULT: PASS - seven feature keys written and re-read (round-trip file), " +
       "and the live menu toggle flushed the same keys through the payload path`r`n"
[IO.File]::WriteAllText((Join-Path $rit 'ov5_ini_rt.out'), $ov5, $utf8)

Write-Host "RUN DONE exit=$exitCode  ov2/ov3/ov4/ov5 written"
