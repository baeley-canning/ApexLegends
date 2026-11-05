# which line calls .Add on a string? p52 (no params, defaults) vs p53 (params).
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o = Join-Path $repo 'temp\p53_dbg2.txt'
function O($t) { $t | Out-File -Append -Encoding utf8 $o }
$p = Join-Path $repo '_ritual\p52_hits.txt'
$out = Join-Path $repo 'temp\p53_dbg2_class.txt'
# pattern probe first: does the arraylist-in-pscustomobject idiom work here?
$Error.Clear()
$probe = [pscustomobject]@{ hits = (New-Object System.Collections.ArrayList); pr = 0 }
$probe.hits.Add('a')
O ('probe_type=' + $probe.hits.GetType().FullName + ' count=' + $probe.hits.Count)
$lst = New-Object 'System.Collections.Generic.List[string]'
$lst.Add('x')
O ('list_type=' + $lst.GetType().FullName)
foreach ($s in @('C:\Windows\Temp\p52_class.ps1', 'C:\Windows\Temp\p53_class.ps1')) {
  $Error.Clear()
  try { & $s -Hits $p -Out $out *> (Join-Path $repo 'temp\p53_dbg2_con.txt') } catch { }
  $e = if ($Error.Count) { ($Error[0].InvocationInfo.PositionMessage -replace "`r?`n", ' ') } else { '-' }
  O ('script=' + $s + ' errs=' + $Error.Count + ' first=' + $e)
  O ('  out_exists=' + [IO.File]::Exists($out) + ' con=' + (((Get-Content -LiteralPath (Join-Path $repo 'temp\p53_dbg2_con.txt') -EA 0 -TotalCount 4) -join ' | ')))
  Remove-Item -LiteralPath $out -EA 0
}
