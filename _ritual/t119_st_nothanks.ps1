# t119_st_nothanks.ps1 - decline passkey, reach REAL landing, final archive touch-up.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t119_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== NOTHANKS'

. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; exit 1 }
$ws2 = $t2.webSocketDebuggerUrl

$dec = @'
(function(){
  var els=document.querySelectorAll('button,a,[role=button]');
  for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').replace(/\s+/g,' ').trim();
    if(/no.?thanks|skip|not now/i.test(t)&&(els[i].offsetWidth||els[i].offsetHeight)){els[i].click();return 'DECLINED:'+t.slice(0,15);}}
  return 'NODECLINE';
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $dec; returnByValue = $true } -Id 970
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('DEC ' + $v1)

# ride 8 legs; ANY url outside signin= home; else stay and describe
$home = 'STILL-ON-SIGNIN'
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = ''
    if ($tb) {
        $qq = Invoke-CdpCmd -WsUrl $tb.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
            expression = "JSON.stringify({ttl:document.title.slice(0,30),h1:(document.querySelector('h1')||{innerText:''}).innerText.replace(/\s+/g,' ').trim().slice(0,40),ava:!!document.querySelector('[class*=avatar],[class*=user-menu],[data-qa*=avatar]')})";
            returnByValue = $true } -Id (971 + $i)
        if ($qq -and $qq.result -and $qq.result.result) { $sq = [string]$qq.result.result.value }
    }
    J ("leg$i " + $sq + ' @' + $u.Substring(0, [Math]::Min(60, $u.Length)))
    if ($u -match 'www\.ea\.com|accounts\.ea\.com' -and $u -notmatch 'signin|juno') { $home = 'TRUE-HOME-REACHED'; break }
    if ($sq -match '"ava":true') { $home = 'HOME-AVATAR'; break }
    if ($sq -match '"ttl":"EA|Home|Welcome') { $home = 'HOME-TTL'; break }
}
$home | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $home")

$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 985
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t119_home.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'HOME SHOT'
    }
    # true-final archive fixups
    $acctPath = Join-Path $here '_ea_account.json'
    if (Test-Path $acctPath) {
        $obj = Get-Content $acctPath -Raw | ConvertFrom-Json
        $obj | Add-Member -NotePropertyName passkeySkipped -NotePropertyValue ($v1 -match 'DECLINED') -Force
        $obj | Add-Member -NotePropertyName finalLanding -NotePropertyValue $tlast.url.Substring(0, [Math]::Min(150, $tlast.url.Length)) -Force
        $obj | Add-Member -NotePropertyName missionVerifiedAt -NotePropertyValue (Get-Date).ToString('s') -Force
        ($obj | ConvertTo-Json) | Out-File -Encoding utf8 $acctPath
        J 'MISSION SEALED IN ARCHIVE'
    }
}
J '=== DONE'
