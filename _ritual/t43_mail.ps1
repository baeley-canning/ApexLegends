# t43_mail.ps1 - make a throwaway mailbox on mail.tm and write address/password/token.
# mail.tm: free JSON API, no key. Writes _t43_mail.txt; the address goes on the EA signup form,
# the token is used by t45_code.ps1 to poll for the verification code.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = "$r\_t43_mail.txt"
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $dom = Invoke-RestMethod -Uri 'https://api.mail.tm/domains?page=1' -Method Get -TimeoutSec 25
  $d = $dom.'hydra:member' | Where-Object { $_.isActive } | Select-Object -First 1
  if (-not $d) { throw 'no active domain' }
  $domain = $d.domain
  $tag = -join ((1..10) | ForEach-Object { 'abcdefghijklmnopqrstuvwxyz0123456789'[(Get-Random -Max 36)] })
  $addr = "apx$tag@$domain"
  $pw = -join ((1..14) | ForEach-Object { 'abcdefghijkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789'[(Get-Random -Max 55)] })
  $body = @{ address = $addr; password = $pw } | ConvertTo-Json
  $acc = Invoke-RestMethod -Uri 'https://api.mail.tm/accounts' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 25
  $tok = Invoke-RestMethod -Uri 'https://api.mail.tm/token' -Method Post -Body (@{ address = $addr; password = $pw } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 25
  @("address=$addr", "password=$pw", "id=$($acc.id)", "token=$($tok.token)", "domain=$domain") | Set-Content -LiteralPath $o
  Write-Host "address=$addr"
} catch {
  "FAILED: $($_.Exception.Message)" | Set-Content -LiteralPath $o
  Write-Host "FAILED: $($_.Exception.Message)"
}
