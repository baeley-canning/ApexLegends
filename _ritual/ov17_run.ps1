# ============================================================================
# _ritual\ov17_run.ps1 - adapter-fix run (R5: new number).
#
# ov11 found it: every Present returned 0x887A0005 DXGI_ERROR_DEVICE_REMOVED.
# Cause - hybrid box, the display hangs off the Intel UHD 730 while
# D3D12CreateDevice(nullptr) hands back the output-less RTX 5060, so the chain
# never had a display to present to.  ov17 creates the device on the adapter with
# a desktop-attached output instead and keeps every ov11 gate (live client rect,
# buffer readback, 80 % coverage).
#
# Evidence: ov17_run.out, ov17_test.png, ov17_desk.png, ov17_buffer.bmp,
# ov17_ocr.txt.  No kernel state involved.
# ============================================================================
param([int] $Seconds = 18, [int] $ShotAt = 7)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\overlay_test.exe'
$cwd  = Join-Path $rit  'ov17_cwd'
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
    -Out (Join-Path $rit 'ov17_test.png')) -join "`r`n"
$deskTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'shot_desk.ps1')) -join "`r`n"
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') `
    -Destination (Join-Path $rit 'ov17_desk.png') -Force

$ocrTxt = (& powershell -ExecutionPolicy Bypass -File `
    (Join-Path $rit 'ocr.ps1') -Path (Join-Path $rit 'ov17_test.png') `
    -Out (Join-Path $rit 'ov17_ocr.txt')) -join "`r`n"

$proc.WaitForExit()
$exitCode = $proc.ExitCode

$resultTxt = '(missing)'
$rp = Join-Path $cwd 'ov_test_result.txt'
if (Test-Path $rp) { $resultTxt = [IO.File]::ReadAllText($rp) }
$bufTxt = '(no buffer dump)'
$bp = Join-Path $cwd 'ov_buffer.bmp'
if (Test-Path $bp) {
    Copy-Item -LiteralPath $bp -Destination (Join-Path $rit 'ov17_buffer.bmp') -Force
    $bufTxt = 'ov_buffer.bmp -> _ritual\ov17_buffer.bmp (' + (Get-Item $bp).Length + ' bytes)'
}
$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\overlay_test_$($proc.Id).log"
$logTxt = '(missing)'
if (Test-Path $logPath) { $logTxt = [IO.File]::ReadAllText($logPath) }

$out = "ov17 - adapter fix (display-attached device) - $stamp`r`n" +
       "exe   : $exe`r`n" +
       "cwd   : $cwd (scratch, emptied first)`r`n" +
       "pid   : $($proc.Id)   exit code: $exitCode  (0 = PASS, 2 = FAIL)`r`n" +
       "shot  : $shotTxt`r`n" +
       "desk  : $deskTxt`r`n" +
       "ocr   : $ocrTxt`r`n" +
       "buffer: $bufTxt`r`n" +
       "---- ov_test_result.txt ----`r`n" + $resultTxt + "`r`n" +
       "---- overlay_test log ----`r`n" + $logTxt + "`r`n"
[IO.File]::WriteAllText((Join-Path $rit 'ov17_run.out'), $out, $utf8)

Write-Host "ov17 DONE exit=$exitCode"
