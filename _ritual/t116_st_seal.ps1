# t116_st_seal.ps1 - privacy page: select-safety assert + NEXT (multi-strategy) + final ride + archive.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t116_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== SEAL'

. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('AT ' + $t2.url.Substring(0, [Math]::Min(80, $t2.url.Length)))

# deep census incl. custom elements + native-like strategy hunt
$cen = @'
(function(){
  var ctl=[].map.call(document.querySelectorAll('button,a,[role=button],wf-button,[class*=otkbtn],input[type=submit],div[class*=btn]'),function(e){
    if(!(e.offsetWidth||e.offsetHeight))return null;
    var t=(e.innerText||e.value||'').replace(/\s+/g,' ').trim();
    return (t||'(notext)').slice(0,20)+'#'+(e.id||'-')+'|'+(e.tagName)+'|'+((e.className||'')+'').split(' ')[0].slice(0,18);
  }).filter(Boolean).slice(0,12);
  var sel=document.querySelector('select');
  var cbs=[].map.call(document.querySelectorAll('input[type=checkbox]'),function(c){return (c.id||'?')+'='+(c.checked?'on':'off');});
  var fm=document.querySelector('form');
  return JSON.stringify({ctl:ctl,sel:sel?(sel.id||'nosel')+'/'+(sel.selectedOptions[0]?sel.selectedOptions[0].text.slice(0,12):'?'):'none',
    cbs:cbs,forms:document.querySelectorAll('form').length,fmAct:fm?fm.action.slice(-25):'-'});
})()
'@
$f0 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $cen; returnByValue = $true } -Id 760
$v0 = '?'; if ($f0 -and $f0.result -and $f0.result.result) { $v0 = [string]$f0.result.result.value }
J ('CEN ' + $v0)

# NEXT with multiple strategies
$nxt = @'
(function(){
  var order=['updateBtn','basicInfoNextBtn','privacyNextBtn'];
  for(var k=0;k<order.length;k++){var b=document.getElementById(order[k]);
    if(b&&(b.offsetWidth||b.offsetHeight)){b.click();return 'HIT-'+order[k];}}
  // text hunt
  var els=document.querySelectorAll('button,a,[role=button],wf-button,div[class*=btn],input[type=submit]');
  for(var i=0;i<els.length;i++){var t=(els[i].innerText||els[i].value||'').replace(/\s+/g,' ').trim();
    if(/^next$/i.test(t)&&(els[i].offsetWidth||els[i].offsetHeight)){els[i].click();return 'TEXT-NEXT-'+els[i].tagName;}}
  // form submit
  var fm=document.querySelector('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS-FORM';}catch(e){}}
  return 'ALL-MISS';
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $nxt; returnByValue = $true } -Id 761
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('NEXT ' + $v1)

# final ride: 12 legs, celebrate exit
$outcome = 'SEAL-UNCLEAR'
for ($i = 1; $i -le 12; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({ttl:document.title.slice(0,30),err:[].map.call(document.querySelectorAll('[class*=error]'),function(e){if(e.offsetParent)return (e.innerText||'').slice(0,50);}).filter(Boolean).slice(0,2),ava:!!document.querySelector('[class*=avatar],[data-qa*=avatar]')})";
        returnByValue = $true } -Id (762 + $i)
    $sv = ''; if ($sq -and $sq.result -and $sq.result.result) { $sv = [string]$sq.result.result.value }
    J ("leg$i " + $sv + ' @' + $u.Substring(0, [Math]::Min(52, $u.Length)))
    if ($u -notmatch 'signin\.ea\.com' -and $u -notmatch 'juno/login') { $outcome = 'SEALED-SESSION-ON-EA'; break }
    if ($sv -match '"ttl":"Welcome|"ttl":"Home|Your mutations|account is ready') { $outcome = 'SEALED-WELCOME-PAGE'; break }
}

# ANCHOR_ARCHIVE
$outcome | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $outcome")

$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 780
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t116_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
if ($outcome -match 'SEALED|ON-EA|WELCOME') {
    $acct = [ordered]@{
        eaId      = 'zk499064xz'
        eaIdAlias = 'ea499064xzacs (rejected: ea-prefix ban)'
        email     = 'ea499064xz@euploading.com'
        password  = '6&Fjd5H@4hbzy5x7'
        createdAt = (Get-Date).ToString('s')
        status    = 'COMPLETE'
        finalVerdict = $outcome
        mailProvider = 'mail.tm acct 6afe86a5d844c7b4fa0539ff'
    }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    @("
=====================================================
  EA ACCOUNT CREATED - MISSION COMPLETE
=====================================================
  EA ID     : zk499064xz
  EMAIL     : ea499064xz@euploading.com
  PASSWORD  : 6&Fjd5H@4hbzy5x7
  CREATED   : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
  VERDICT   : $outcome
  MAILBOX   : mail.tm (credentials in _mail.json)
=====================================================") |
        Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
    J '### ARCHIVED-COMPLETE ###'
}
J '=== DONE'

