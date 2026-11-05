while ($true) {
  $n=@(Get-Content $args[0]\_h131_soak.log -EA 0).Count
  if (Test-Path $args[0]\_h131_soak.log) { $last=(Get-Content $args[0]\_h131_soak.log -Tail 1) } else { $last='' }
  if ($last -match 'SOAK_VERDICT') { ($last + ' n=' + $n) | Out-File "$($args[0])\_h154_GATE.txt" -Encoding UTF8; break }
  Start-Sleep -Seconds 20
}
