# debug: why does ReadLines fail on the fixture?
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o = Join-Path $repo 'temp\p53_dbg.txt'
function O($t) { $t | Out-File -Append -Encoding utf8 $o }
O ('psversion=' + $PSVersionTable.PSVersion)
O ('eap=' + $ErrorActionPreference)
$p = Join-Path $repo '_ritual\p52_hits.txt'
O ('exists=' + [IO.File]::Exists($p))
try { O ('len=' + (Get-Item -LiteralPath $p).Length) } catch { O ('len ERR ' + $_.Exception.Message) }
try {
  $n = 0
  foreach ($l in [IO.File]::ReadLines($p)) { $n++ }
  O ('readlines_ok lines=' + $n)
} catch { O ('readlines_ERR ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message) }
$out = Join-Path $repo 'temp\p53_dbg_class.txt'
& 'C:\Windows\Temp\p53_class.ps1' -Hits $p -Out $out *> (Join-Path $repo 'temp\p53_dbg_con.txt')
O ('class_exit=' + $LASTEXITCODE + ' out_exists=' + [IO.File]::Exists($out))
O ('head=' + ((Get-Content -LiteralPath (Join-Path $repo 'temp\p53_dbg_con.txt') -EA 0 -TotalCount 3) -join ' | '))
