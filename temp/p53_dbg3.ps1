# exact line of the .Add failure in the p53 copy
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o = Join-Path $repo 'temp\p53_dbg3.txt'
function O($t) { $t | Out-File -Append -Encoding utf8 $o }
$p = Join-Path $repo '_ritual\p52_hits.txt'
$o2 = Join-Path $repo 'temp\p53_dbg3_class.txt'
$ErrorActionPreference = 'Stop'
O ('start ' + (Get-Date -f 'HH:mm:ss'))
try {
  . 'C:\Windows\Temp\p53_class.ps1' -Hits $p -Out $o2 *> (Join-Path $repo 'temp\p53_dbg3_con.txt')
  O 'no_error'
} catch {
  O ('HIT ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message)
  O ('line=' + $_.InvocationInfo.ScriptLineNumber + ' text=[' + $_.InvocationInfo.Line + ']')
  O ('stack=' + ($_.ScriptStackTrace -replace "`r?`n", ' <- '))
  O ('target=' + $_.TargetObject)
}
O ('out_exists=' + [IO.File]::Exists($o2) + ' end ' + (Get-Date -f 'HH:mm:ss'))
