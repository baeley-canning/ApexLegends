# t121_polish.ps1 - correct $HOME-collision fields with journaled truth; final ledger summary.
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$p = Join-Path $here '_ea_account.json'
$obj = Get-Content $p -Raw | ConvertFrom-Json
$obj.postFinish = 'BOOM-page acknowledged; finish routed to terms gate (t117 journal)'
$obj.postTermsLanding = 'passkey upsell declined; true home www.ea.com reached (t120 journal)'
$obj | Add-Member -NotePropertyName missionComplete -NotePropertyValue $true -Force
$obj | ConvertTo-Json | Out-File -Encoding utf8 $p
Get-Content $p
