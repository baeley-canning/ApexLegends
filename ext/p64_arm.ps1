$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$cmd = Join-Path $root 'temp\cmd.txt'
$out = Join-Path $root 'temp\cmd_out.txt'
Add-Content -LiteralPath $out -Value ('LISTENER UP ' + (Get-Date -Format HH:mm:ss))
Set-Location $root
while ($true) {
  if (Test-Path $cmd) {
    # Torn-write guard: a queued job only counts when it is complete (non-NUL body,
    # trailing newline).  A Copy-Item in flight leaves a NUL-prefixed stub behind.
    $c = ''
    try { $c = Get-Content $cmd -Raw } catch { $c = '' }
    if ($c) { $c = $c.Replace([string][char]0, '').Trim() } else { $c = '' }
    if ($c -match "`n\s*$" -or ($c.Length -gt 0 -and $c -notmatch '[^\x20-\x7e\r\n]')) {
      Remove-Item $cmd -Force
      Add-Content -LiteralPath $out -Value ('RUN ' + (Get-Date -Format HH:mm:ss) + ' :: ' + $c)
      try { Invoke-Expression $c *>&1 | Out-File -FilePath $out -Append -Width 400 } catch { 'ERR ' + $_ | Out-File -FilePath $out -Append }
    }
  }
  Start-Sleep -Milliseconds 300
}
