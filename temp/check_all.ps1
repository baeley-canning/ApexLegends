# check_all - 19/11: syntax+behavior validation for tonight's new helpers.
# Writes temp\syntax_check.txt. Runs: python ast parse of qk_harvest.py,
# REAL dry-run of qk_harvest.py (feed absent -> FEED MISSING branch),
# PSParser tokenize of qk_pulse.ps1 / bridge_keeper.ps1.
$t='C:\Users\New User\OneDrive\Desktop\cheating\temp'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$o=Join-Path $t 'syntax_check.txt'
('CHECK_TIME='+(Get-Date -Format 'HH:mm:ss')) | Set-Content -LiteralPath $o
# -- python: ast parse --
$code = 'import ast; src=open(r"' + (Join-Path $t 'qk_harvest.py') + '",encoding="utf-8").read(); ast.parse(src); print("AST_OK")'
$pyout = & $py -c $code 2>&1 | Out-String
('PY_AST: ' + $pyout.Trim()) | Add-Content -LiteralPath $o
# -- python: behavioral dry-run (no feed yet) --
$pyout2 = & $py (Join-Path $t 'qk_harvest.py') 2>&1 | Out-String
'DRY_RUN_STDOUT:' | Add-Content -LiteralPath $o
$pyout2.Trim() | Add-Content -LiteralPath $o
'HARVEST_FILE_CONTENTS:' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'harvest_out.txt') -EA SilentlyContinue | Add-Content -LiteralPath $o
# -- powershell: tokenizer --
foreach($fn in 'qk_pulse.ps1','bridge_keeper.ps1'){
  $errs=$null
  [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content -Raw (Join-Path $t $fn)), [ref]$errs) | Out-Null
  ('PS_TOKENIZE {0}: errs={1}' -f $fn, $errs.Count) | Add-Content -LiteralPath $o
}
'DONE' | Add-Content -LiteralPath $o
