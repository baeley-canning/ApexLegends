# ============================================================================
# _ritual\ov56_run.ps1 - late-queue run (R5: new number, one variable).
#
# Variable vs ov55: the overlay NO LONGER gets the creating queue up front.  It
# is delivered at frame 60 (--late-queue 60), i.e. after the renderer already had
# to build itself on a private queue.  That is the exact in-game order, because
# in game the queue can only ever arrive from the ExecuteCommandLists hook and
# the first frames are necessarily queue-less.
#
# What must hold:
#   * 60 frames are held without a submit (no device removal while queue-less),
#   * the queue is accepted and the overlay ends on it (UsesOwnQueue() == 0),
#   * the ov55 gates still hold: presentFails = 0, coverage >= 80 %, full bbox.
# Two runs back to back: a PASS has to reproduce.
#
# Evidence: ov56_run.out, ov56a/b_test.png, ov56a/b_desk.png, ov56a/b_ocr.txt.
# No kernel state involved.
# ============================================================================
param([int] $Seconds = 20, [int] $ShotAt = 8)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\overlay_test.exe'
$cwd  = Join-Path $rit  'ov56_cwd'
$utf8 = [Text.UTF8Encoding]::new($false)

if (-not (Test-Path $exe)) { throw "overlay_test.exe missing: $exe" }
[void][IO.Directory]::CreateDirectory($cwd)

$out = "ov56 - late queue delivery (in-game order) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"

foreach ($tag in @('a', 'b')) {
    foreach ($f in [IO.Directory]::GetFiles($cwd)) { [IO.File]::Delete($f) }

    $proc = Start-Process -FilePath $exe `
        -ArgumentList @("--seconds $Seconds", "--late-queue 60", "--outdir `"$cwd`"") `
        -WorkingDirectory $cwd -PassThru
    Start-Sleep -Seconds $ShotAt

    $shotTxt = (& powershell -ExecutionPolicy Bypass -File `
        (Join-Path $rit 'shot_win.ps1') -Title 'QwenKern Overlay Test' `
        -Out (Join-Path $rit "ov56$tag`_test.png")) -join "`r`n"
    (& powershell -ExecutionPolicy Bypass -File `
        (Join-Path $rit 'shot_desk.ps1')) | Out-Null
    Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') `
        -Destination (Join-Path $rit "ov56$tag`_desk.png") -Force
    $ocrTxt = (& powershell -ExecutionPolicy Bypass -File `
        (Join-Path $rit 'ocr.ps1') -Path (Join-Path $rit "ov56$tag`_test.png") `
        -Out (Join-Path $rit "ov56$tag`_ocr.txt")) -join "`r`n"

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode

    $resultTxt = '(missing)'
    $rp = Join-Path $cwd 'ov_test_result.txt'
    if (Test-Path $rp) { $resultTxt = [IO.File]::ReadAllText($rp) }
    $logPath = Join-Path $env:LOCALAPPDATA "QwenKern\overlay_test_$($proc.Id).log"
    $logTxt = '(missing)'
    if (Test-Path $logPath) { $logTxt = [IO.File]::ReadAllText($logPath) }

    $out += "`r`n===== run $tag =====`r`n" +
            "pid   : $($proc.Id)   exit code: $exitCode  (0 = PASS, 2 = FAIL)`r`n" +
            "shot  : $shotTxt`r`n" +
            "ocr   : $ocrTxt`r`n" +
            "---- ov_test_result.txt ----`r`n" + $resultTxt + "`r`n" +
            "---- overlay_test log ----`r`n" + $logTxt + "`r`n"
    Write-Host "ov56 run $tag exit=$exitCode"
}

[IO.File]::WriteAllText((Join-Path $rit 'ov56_run.out'), $out, $utf8)
Write-Host 'ov56 DONE'
