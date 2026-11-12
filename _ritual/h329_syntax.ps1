# h329_syntax.ps1 - parser-evidence for the h328/h329 script set (R3: write result, read result).
# Read-only: parses only, no state change.
$ErrorActionPreference = 'Stop'
$files = @(
  '_ritual\s2_stage_v14.ps1',
  '_ritual\s2_load_v14.ps1',
  '_ritual\h328_vadbase.ps1',
  '_ritual\g329_readonly.ps1',
  '_ritual\h329_vmbench.ps1',
  '_ritual\h329_fire_readonly.ps1'
)
$out = @('h329 syntax evidence ' + (Get-Date -Format s))
$fail = $false
foreach ($f in $files) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f).Path, [ref]$null, [ref]$errs)
    if ($errs.Count -gt 0) {
        $fail = $true
        $out += ('SYNTAX-FAIL ' + $f)
        $errs | ForEach-Object { $out += ('  L' + $_.Extent.StartLineNumber + ': ' + $_.Message) }
    } else {
        $out += ('SYNTAX-OK ' + $f)
    }
}
$out += ('VERDICT: ' + $(if ($fail) { 'FAIL' } else { 'ALL-SIX-PARSE-CLEAN' }))
Set-Content '_ritual\h329_syntax.txt' $out
Get-Content '_ritual\h329_syntax.txt'
