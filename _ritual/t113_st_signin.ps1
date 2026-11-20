# t113_st_signin.ps1 - password stage: wait-hydration, fill, sign-in, classify outcome.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t113_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== SIGNIN'

. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'juno/login' }) | Select-Object -First 1
if (-not $t2) { J 'NO LOGIN TAB'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('AT s' + ($t2.url | Select-String -Pattern 's(\d+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }))

# hydrate wait
$hydrated = $false
for ($i = 1; $i -le 10; $i++) {
    $hp = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({pw:!!document.querySelector('input[type=password]'),btns:[].map.call(document.querySelectorAll('button'),function(e){if(!(e.offsetWidth||e.offsetHeight))return null;return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,20)+'#'+(e.id||'-');}).filter(Boolean).slice(0,6),ins:[].map.call(document.querySelectorAll('input:not([type=hidden])'),function(e){return (e.id||'-')+'/'+e.type;}).slice(0,6)})";
        returnByValue = $true } -Id (660 + $i)
    $hv = ''; if ($hp -and $hp.result -and $hp.result.result) { $hv = [string]$hp.result.result.value }
    J ("hyd$i $hv")
    if ($hv -match '"pw":true') { $hydrated = $true; break }
    Start-Sleep -Seconds 3
}

# ANCHOR_DOFILL
if ($hydrated) {
    $fill = @'
(function(){
  function fs(el,v){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v);['keydown','keypress','input','keyup','change'].forEach(function(t){
    el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});}
  var pw=document.querySelector('input[type=password]');
  fs(pw,'6&Fjd5H@4hbzy5x7');
  var em=document.getElementById('email');
  if(em&&!em.value) fs(em,'ea499064xz@euploading.com');
  var btn=null;var bs=document.querySelectorAll('button,[role=button]');
  for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||'').replace(/\s+/g,' ').trim();
    if(/^(sign ?in|log ?in|next)$/i.test(t)&&(bs[i].offsetWidth||bs[i].offsetHeight)){btn=bs[i];break;}}
  if(!btn) btn=document.getElementById('logInBtn');
  if(btn){btn.click();return 'SIGNED:'+((btn.innerText||'').slice(0,14));}
  var fm=pw.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS-IN';}catch(e){}}
  return 'NOBTN';
})()
'@
    $ff = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $fill; returnByValue = $true } -Id 672
    $fv = '?'; if ($ff -and $ff.result -and $ff.result.result) { $fv = [string]$ff.result.result.value }
    J ('DO ' + $fv)
} else { J 'NEVER HYDRATED' }

# classify
$verdict = 'LOGIN-UNCLEAR'
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({s:(location.href.match(/s(\\d+)&/)||[])[1],err:[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){if(e.offsetParent)return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,80);}).filter(Boolean).slice(0,3),ava:!!document.querySelector('[class*=avatar],[data-testid*=avatar],img[alt*=avatar i]')})";
        returnByValue = $true } -Id (680 + $i)
    $sv = ''; if ($sq -and $sq.result -and $sq.result.result) { $sv = [string]$sq.result.result.value }
    J ("cls$i " + $sv + ' u=' + $u.Substring(0, [Math]::Min(60, $u.Length)))
    if ($sv -match 'match|found|invalid|exist|locked|too many|verify') {
        $verdict = if ($sv -match 'match|incorrect') { 'WRONG-PASSWORD' } elseif ($sv -match 'found|exist') { 'NO-ACCOUNT' } else { 'ERROR:' + ($sv.Slice(0, 40)) }
        if ($sv -match 'verify') { $verdict = 'LOGIN-NEEDS-VERIFY-INTERSTITIAL' }
        break
    }
    if ($u -notmatch 'juno/login' -and $u -notmatch 'signin\.ea\.com') { $verdict = 'LOGIN-SESSION-OK'; break }
    if ($u -match 'ea\.com(?!.*/login)' -and $u -notmatch 'signin') { $verdict = 'LOGIN-SESSION-OK'; break }
}

$verdict | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $verdict")
$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 700
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t113_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
J '=== DONE'

