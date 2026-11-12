# ============================================================================
# _ritual\ov7_run.ps1 - re-run build\overlay_test.exe after the 07/11 crash,
# fresh evidence under new numbers (R5): ov7_test.png / ov7_ocr.txt / ov7_run.out
# and ov7_ini.txt.  Same protocol as ov_run_test.ps1 (T6), no kernel state.
# ============================================================================
param([int] $Seconds = 16, [int] $ShotAt = 8)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\overlay_test.exe'
$cwd  = Join-Path $rit  'ov7_cwd'
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
    -Out (Join-Path $rit 'ov7_test.png')) -join "`r`n"

$ocrTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'ocr.ps1') -Path (Join-Path $rit 'ov7_test.png') `
    -Out (Join-Path $rit 'ov7_ocr.txt')) -join "`r`n"

$proc.WaitForExit()
$exitCode = $proc.ExitCode

$resultTxt = '(missing)'
$rp = Join-Path $cwd 'ov_test_result.txt'
if (Test-Path $rp) { $resultTxt = [IO.File]::ReadAllText($rp) }
$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\overlay_test_$($proc.Id).log"
$logTxt = '(missing)'
if (Test-Path $logPath) { $logTxt = [IO.File]::ReadAllText($logPath) }

$out = "ov7 - overlay_test re-run after 0x3B crash - $stamp`r`n" +
       "exe   : $exe`r`n" +
       "cwd   : $cwd (scratch, emptied first)`r`n" +
       "pid   : $($proc.Id)   exit code: $exitCode  (0 = PASS, 2 = FAIL)`r`n" +
       "shot  : $shotTxt`r`n" +
       "ocr   : $ocrTxt`r`n" +
       "---- ov_test_result.txt ----`r`n" + $resultTxt + "`r`n" +
       "---- overlay_test log ----`r`n" + $logTxt + "`r`n"
[IO.File]::WriteAllText((Join-Path $rit 'ov7_run.out'), $out, $utf8)

$iniTxt = if (Test-Path (Join-Path $cwd 'apexcheat.ini')) {
    [IO.File]::ReadAllText((Join-Path $cwd 'apexcheat.ini')) } else { '(missing)' }
[IO.File]::WriteAllText((Join-Path $rit 'ov7_ini.txt'),
    "ov7 - live menu toggle ini flush - $stamp`r`n$iniTxt`r`n", $utf8)

Write-Host "OV7 DONE exit=$exitCode"
