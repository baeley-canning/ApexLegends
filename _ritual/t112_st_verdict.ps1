# t112_st_verdict.ps1 - exact-id login attempt; fallback forgot-password; mailbox confirmation.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t112_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== VERDICT'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't88_lib.ps1')

$m0 = Get-T88-Mail $hdr
$baseId = if ($m0) { $m0.id } else { '' }

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('AT ' + $t2.url.Substring(0, [Math]::Min(80, $t2.url.Length)))

# ANCHOR_A_LOGIN
$try = @'
(function(){
  function fs(el,v){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v);['keydown','keypress','input','keyup','change'].forEach(function(t){
    el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});el.blur();}
  var em=document.getElementById('email');
  var pw=document.getElementById('password');
  if(em) fs(em,'ea499064xz@euploading.com');
  if(pw) fs(pw,'6&Fjd5H@4hbzy5x7');
  var lb=document.getElementById('logInBtn');
  if(lb){lb.click();return 'PRESSED-LOGIN';}
  return 'NOLOGINBTN';
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $try; returnByValue = $true } -Id 611
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('LOGIN ' + $v1)

# ride: 8 x 3.5s — password slide-out sign-in, errors, or page exit
$verdict = 'LOGIN-UNCLEAR'
$firedSecond = $false
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Milliseconds 3500
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sh = ''; if ($u -match 'execution=[^&]*s(\d+)') { $sh = $Matches[1] }
    # in-page sig
    $sg = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({s:(location.href.match(/s(\\d+)&/)||[])[1],pw:!!document.querySelector('input[type=password]'),err:[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){if(e.offsetParent)return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,65);}).filter(Boolean).slice(0,3),bt:[].map.call(document.querySelectorAll('button'),function(e){if(!(e.offsetWidth||e.offsetHeight))return null;return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,18);}).filter(Boolean).slice(0,6)})";
        returnByValue = $true } -Id (612 + $i)
    $sv = ''; if ($sg -and $sg.result -and $sg.result.result) { $sv = [string]$sg.result.result.value }
    J ("o$i s$sh " + $sv)
    # second-stage sign-in?
    if (-not $firedSecond -and $sv -match '"pw":true' -and $sv -match '"s":"2"') {
        $second = @'
(function(){
  var pw=document.querySelector('input[type=password]');
  if(pw&&!pw.value){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(pw,'6&Fjd5H@4hbzy5x7');['keydown','keypress','input','keyup','change'].forEach(function(t){
    pw.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});pw.blur();}
  var bs=document.querySelectorAll('button,[role=button]');
  for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||'').replace(/\s+/g,' ').trim();
    if(/^sign ?in$/i.test(t)&&(bs[i].offsetWidth||bs[i].offsetHeight)){bs[i].click();return 'SIGN2';}}
  var lb=document.getElementById('logInBtn'); if(lb){lb.click();return 'LOGIN2';}
  return 'NOSIGN';
})()
'@
        $fs2 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $second; returnByValue = $true } -Id (625)
        J ('SECOND ' + $(if ($fs2 -and $fs2.result) { [string]$fs2.result.result.value } else { '?' }))
        $firedSecond = $true
    }
    if ($sv -match 'match|found|invalid|locked|exist') { $verdict = 'NO-ACCOUNT-OR-BADCREDS'; break }
    if ($u -notmatch 'juno/login') { $verdict = 'LOGIN-SESSION-OK'; break }
    if ($sv -match '"s":"(s?[3-9]|1[0-9])"') { $verdict = 'LOGIN-ADVANCED-STEP'; }
}

# ANCHOR_B_FORGOT
if ($verdict -in @('LOGIN-UNCLEAR','NO-ACCOUNT-OR-BADCREDS')) {
    J 'ENGAGING FORGOT-ORACLE'
    # click forgot link
    $fg = @'
(function(){
  var els=document.querySelectorAll('a,button,[role=link]');
  for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').replace(/\s+/g,' ');
    if(/forgot/i.test(t)&&(els[i].offsetWidth||els[i].offsetHeight)){els[i].click();return 'FG-CLICK';}}
  return 'FG-MISS';
})()
'@
    $ff = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $fg; returnByValue = $true } -Id 630
    J ('FORGOT ' + $(if ($ff -and $ff.result) { [string]$ff.result.result.value } else { '?' }))
    Start-Sleep -Seconds 5

    # re-find tab, census reset page
    $tabs3 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $t3 = @($tabs3 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    if ($t3) {
        J ('FGPG ' + $t3.url.Substring(0, [Math]::Min(80, $t3.url.Length)))
        $rst = @'
(function(){
  var em=document.querySelector('input[type=email],#email,input[name=email],input[id*=email]');
  if(!em) return 'NO-FIELD';
  var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
  st.call(em,'ea499064xz@euploading.com');
  ['keydown','keypress','input','keyup','change'].forEach(function(t){
    em.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});
  em.blur();
  var bm=document.querySelectorAll('button,input[type=submit],[role=button],a[class*=btn]');
  for(var i=0;i<bm.length;i++){var t=(bm[i].innerText||bm[i].value||'').replace(/\s+/g,' ').trim();
    if(/^(send|next|reset|submit|continue)/i.test(t)&&(bm[i].offsetWidth||bm[i].offsetHeight)){
      if((bm[i].className||'').indexOf('disabled')>=0) continue;
      bm[i].click();return 'SENT:'+t.slice(0,18);}}
  var fm=em.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS-SENT';}catch(e){}}
  return 'NO-BTN';
})()
'@
        $fr = Invoke-CdpCmd -WsUrl $t3.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{ expression = $rst; returnByValue = $true } -Id 631
        $vr = '?'; if ($fr -and $fr.result -and $fr.result.result) { $vr = [string]$fr.result.result.value }
        J ('RESET ' + $vr)

        if ($vr -match 'SENT|RS') {
            for ($i = 1; $i -le 8; $i++) {
                Start-Sleep -Seconds 5
                try {
                    $mm = Get-T88-Mail $hdr
                    if ($mm -and $mm.id -ne $baseId) {
                        J ('RESETMAIL ' + $mm.subject)
                        $verdict = 'ACCOUNT-EXISTS-RESET-MAIL-ARRIVED'
                        break
                    }
                } catch { Start-Sleep -Seconds 3 }
            }
        }
    }
}

$verdict | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $verdict")

$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 650
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t112_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
J '=== DONE'


