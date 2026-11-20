# t120_st_decline2.ps1 - punctuation-proof passkey decline + ride home + final archive.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t120_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== DECLINE2'

. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; exit 1 }
$ws2 = $t2.webSocketDebuggerUrl

# census once for the record
$cz = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
    expression = "JSON.stringify([].map.call(document.querySelectorAll('button,a,[role=button]'),function(e){if(!(e.offsetWidth||e.offsetHeight))return null;return (e.innerText||'').replace(/[^A-Za-z ]/g,' ').replace(/\s+/g,' ').trim().slice(0,18)+'#'+(e.id||'-');}).filter(Boolean).slice(0,8))";
    returnByValue = $true } -Id 990
if ($cz -and $cz.result -and $cz.result.result) { J ('CEN ' + [string]$cz.result.result.value) }

# normalized-text decliner
$dec = @'
(function(){
  var els=document.querySelectorAll('button,a,[role=button]');
  var norm=function(s){return (s||'').replace(/[^A-Za-z ]/g,' ').replace(/\s+/g,' ').trim().toLowerCase();};
  for(var i=0;i<els.length;i++){
    if(!(els[i].offsetWidth||els[i].offsetHeight))continue;
    var t=norm(els[i].innerText);
    if(/\bno\b.*\bthanks\b/.test(t)||/\bskip\b/.test(t)||/\bnot now\b/.test(t)||(els[i].id==='laterBtn')){
      els[i].click();return 'DECLINED:'+(els[i].id||t.slice(0,14));
    }
  }
  return 'STILL-NODECLINE';
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $dec; returnByValue = $true } -Id 991
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('DEC2 ' + $v1)

# ride 8
$home = 'PASSKEY-GATE-HELD'
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = ''
    if ($tb) {
        $qq = Invoke-CdpCmd -WsUrl $tb.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
            expression = "JSON.stringify({ttl:document.title.slice(0,28),h1:(document.querySelector('h1')||{innerText:''}).innerText.replace(/\s+/g,' ').trim().slice(0,38)})";
            returnByValue = $true } -Id (992 + $i)
        if ($qq -and $qq.result -and $qq.result.result) { $sq = [string]$qq.result.result.value }
    }
    J ("leg$i " + $sq + ' @' + $u.Substring(0, [Math]::Min(58, $u.Length)))
    if ($u -match 'www\.ea\.com|accounts\.ea\.com' -and $u -notmatch 'signin|juno') { $home = 'TRUE-HOME'; break }
    if ($sq -match 'passkey') { continue }
    if ($sq -notmatch 'passkey' -and $sq -ne '') { $home = 'PAST-PASSKEY:' + $sq.slice(0, 30); break }
}

$home | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $home")
$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 999
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t120_home.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOTS'
    }
    $acctPath = Join-Path $here '_ea_account.json'
    if (Test-Path $acctPath) {
        $obj = Get-Content $acctPath -Raw | ConvertFrom-Json
        $obj | Add-Member -NotePropertyName passkeySkipped -NotePropertyValue ($v1 -match 'DECLINED') -Force
        $obj | Add-Member -NotePropertyName finalLanding -NotePropertyValue $tlast.url.Substring(0, [Math]::Min(140, $tlast.url.Length)) -Force
        ($obj | ConvertTo-Json) | Out-File -Encoding utf8 $acctPath
        J 'ARCHIVE FINAL'
    }
}
J '=== DONE'
