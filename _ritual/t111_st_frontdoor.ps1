# t111_st_frontdoor.ps1 - enter via www.ea.com/login (fresh SSO), census, login attempt.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t111_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== FRONTDOOR'

. (Join-Path $here '_cdp.ps1')

# pick the stray login tab (any non-wizard)
$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO STRAY TAB'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('TAB0 ' + $t2.url.Substring(0, [Math]::Min(70, $t2.url.Length)))

# front door
Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
    expression = "location.assign('https://www.ea.com/login')"; returnByValue = $true } -Id 580 | Out-Null
J 'FRONTDOOR NAV'
Start-Sleep -Seconds 10

# re-attach (redirects likely)
$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'TAB LOST POSTNAV'; 'LOST' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('LANDED ' + $t2.url.Substring(0, [Math]::Min(85, $t2.url.Length)))

# census loop
$census = ''
for ($i = 1; $i -le 7; $i++) {
    $cf = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({u:location.href.slice(-45),n:document.querySelectorAll('input:not([type=hidden])').length,ins:[].map.call(document.querySelectorAll('input:not([type=hidden])'),function(e){return (e.id||e.name||'-')+'/'+e.type;}).slice(0,6),btns:[].map.call(document.querySelectorAll('button,[role=button],input[type=submit]'),function(e){if(!(e.offsetWidth||e.offsetHeight))return null;return (e.innerText||e.value||'').replace(/\s+/g,' ').trim().slice(0,20)+'#'+(e.id||'-');}).filter(Boolean).slice(0,8)})";
        returnByValue = $true } -Id (581 + $i)
    $cv = ''; if ($cf -and $cf.result -and $cf.result.result) { $cv = [string]$cf.result.result.value }
    J ("c$i $cv")
    $census = $cv
    if ($cv -match '"n":[1-9]') { break }
    Start-Sleep -Seconds 3
}

# ANCHOR_LOGINATTEMPT
if ($census -match '"n":[1-9]') {
    $doLogin = @'
(function(){
  function fs(el,v){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v);['keydown','keypress','input','keyup','change'].forEach(function(t){
    el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});el.blur();}
  var em=document.querySelector('input[type=email],input[id*=email],input[name=email]');
  var pw=document.querySelector('input[type=password]');
  if(!em||!pw) return 'FIELDS:'+document.querySelectorAll('input').length;
  fs(em,'ea499064xz@euploading.com'); fs(pw,'6&Fjd5H@4hbzy5x7');
  var btn=null;var bs=document.querySelectorAll('button,[role=button],input[type=submit],a[class*=btn]');
  for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||bs[i].value||'').replace(/\s+/g,' ').trim();
    if(/log ?in|sign ?in/i.test(t)&&!/out/i.test(t)&&(bs[i].offsetWidth||bs[i].offsetHeight)){btn=bs[i];break;}}
  if(btn){btn.click();return 'CLICKED:'+(btn.innerText||btn.value).slice(0,15);}
  var fm=em.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS';}catch(e){return 'RSERR';}}
  return 'NOBTN';
})()
'@
    $f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $doLogin; returnByValue = $true } -Id 590
    $v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
    J ('LOGINTRY ' + $v1)

    $verdict = 'LOGIN-UNCLEAR'
    for ($i = 1; $i -le 7; $i++) {
        Start-Sleep -Seconds 3
        $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
        $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
        $u = if ($tb) { $tb.url } else { '(gone)' }
        J ("o$i " + $u.Substring(0, [Math]::Min(75, $u.Length)))
        if ($tb) {
            if ($tb.url -match 'juno/login' -or $tb.url -match 'signin\.ea\.com') {
                $errq = Invoke-CdpCmd -WsUrl $tb.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
                    expression = "JSON.stringify([].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){if(e.offsetParent)return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,70);}).filter(Boolean).slice(0,3))";
                    returnByValue = $true } -Id (600 + $i)
                $ev = ''; if ($errq -and $errq.result -and $errq.result.result) { $ev = [string]$errq.result.result.value }
                J ("e$i " + $ev)
                if ($ev -match 'found|invalid|incorrect|mismatch|locked') { $verdict = 'NO-ACCOUNT-OR-BADCREDS'; break }
            } else {
                $verdict = 'LOGIN-SESSION-OK'
                break
            }
        }
    }
} else {
    $verdict = 'FRONTDOOR-DEAD-NOFORM'
    J 'front door rendered no form'
}
$verdict | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $verdict")

$tb2 = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tb2) {
    $s = Invoke-CdpCmd -WsUrl $tb2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 610
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t111_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
J '=== DONE'

