$ErrorActionPreference = 'Stop'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\mail.json'
$pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) + '!Q7z'
$domains = (Invoke-RestMethod -Uri 'https://api.mail.tm/domains' -TimeoutSec 25).'hydra:member'
foreach($d in $domains){
  $addr = ('kern' + (Get-Random -Minimum 10000 -Maximum 99999) + '@' + $d.domain)
  $body = @{ address = $addr; password = $pw } | ConvertTo-Json
  try {
    $acct = Invoke-RestMethod -Uri 'https://api.mail.tm/accounts' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 25
    $tok  = (Invoke-RestMethod -Uri 'https://api.mail.tm/token' -Method Post -Body (@{ address = $addr; password = $pw } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 25).token
    @{ address = $addr; password = $pw; id = $acct.id; token = $tok } | ConvertTo-Json | Set-Content -LiteralPath $out -Encoding utf8
    "OK $addr" | Set-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_probe.txt'
    exit 0
  } catch {
    "fail $addr : $($_.Exception.Message)" | Add-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_probe.txt'
  }
}
'ALLDOMAINSFAILED' | Add-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_probe.txt'
exit 1
