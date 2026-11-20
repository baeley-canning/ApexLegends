# t118_st_terms.ps1 - tick updated-terms + NEXT, ride to session landing, final verify + archive polish.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t118_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== TERMS'

. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('AT ' + $t2.url.Substring(0, [Math]::Min(80, $t2.url.Length)))

# tick + next (explicit-id tolerant)
$tx = @'
(function(){
  function fs(el,v){/*noop*/}
  var chk=document.getElementById('readAccept')||document.querySelector('input[type=checkbox]');
  var cs='noChk';
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();cs=chk.checked?'ticked':'refused';}
  var nb=document.getElementById('nextBtn')||document.getElementById('logInBtn');
  var pressed='-';
  if(nb&&(nb.offsetWidth||nb.offsetHeight)){
    var lk=(nb.className||'').indexOf('disabled')>=0;
    nb.click();pressed='btn-'+(lk?'blind':'live');
  } else {
    var els=document.querySelectorAll('button,a,[role=button]');
    for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').replace(/\s+/g,' ').trim();
      if(/^next$/i.test(t)&&(els[i].offsetWidth||els[i].offsetHeight)){els[i].click();pressed='txt-next';break;}}
    if(pressed==='-'){var fm=document.querySelector('form');
      if(fm&&fm.requestSubmit){try{fm.requestSubmit();pressed='rs';}catch(e){}}}
  }
  return JSON.stringify({chk:cs,pressed:pressed});
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $tx; returnByValue = $true } -Id 950
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('TICK ' + $v1)

# ride 10
$home = 'TERMS-UNRESOLVED'
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = ''
    if ($tb) {
        $qq = Invoke-CdpCmd -WsUrl $tb.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
            expression = "JSON.stringify({ttl:document.title.slice(0,32),ava:!!document.querySelector('[class*=avatar],[data-qa*=avatar],[class*=user-menu]'),h1:(document.querySelector('h1')||{innerText:''}).innerText.replace(/\s+/g,' ').trim().slice(0,40)})";
            returnByValue = $true } -Id (951 + $i)
        if ($qq -and $qq.result -and $qq.result.result) { $sq = [string]$qq.result.result.value }
    }
    J ("leg$i " + $sq + ' @' + $u.Substring(0, [Math]::Min(58, $u.Length)))
    if ($u -match 'www\.ea\.com' -and $u -notmatch 'signin|juno') { $home = 'HOME-EA-COM-REACHED'; break }
    if ($sq -match '"ava":true|h1.*(download|play|home|welcom)') { $home = 'HOME-SIGNS-YES'; break }
}

# ANCHOR_TAIL
$home | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $home")

$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 965
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t118_home.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'HOME SHOT'
    }
}
# refresh archive with terms status
$acct = Get-Content (Join-Path $here '_ea_account.json') -Raw -ErrorAction SilentlyContinue
if ($acct) {
    $obj = $acct | ConvertFrom-Json
    $obj | Add-Member -NotePropertyName termsAccepted -NotePropertyValue ($home -notmatch 'UNRESOLVED') -Force
    $obj | Add-Member -NotePropertyName postTermsLanding -NotePropertyValue $home -Force
    ($obj | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J 'ARCHIVE POLISHED'
}
J '=== DONE'

