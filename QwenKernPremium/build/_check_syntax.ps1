# Parse-only check: does each script compile?  Nothing is executed.
$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$files = @(
    (Join-Path $root 'build\enable_testsigning.ps1'),
    (Join-Path $root 'build\_resume_after_testsigning.ps1'),
    (Join-Path $root 'build\sign_and_test_driver.ps1'),
    (Join-Path $root 'build\_probe_bcd.ps1')
)
$out = Join-Path $root 'build\phase1_evidence\_syntax.txt'
$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) {
        $lines.Add("FAIL $f")
        foreach ($e in $errs) { $lines.Add(("  line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)) }
    } else {
        $lines.Add("OK   $f")
    }
}
$lines | Set-Content -Encoding utf8 $out
$lines | ForEach-Object { Write-Host $_ }
