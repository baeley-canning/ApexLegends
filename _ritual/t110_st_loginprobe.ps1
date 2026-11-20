# t110_st_loginprobe.ps1 - reuse login tab, wait-for-render, login with credentials, detect session.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t110_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== LOGINPROBE'

. (Join-Path $here '_cdp.ps1')

# attach to the EXISTING login tab
$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'juno/login' }) | Select-Object -First 1
if (-not $t2) {
    # nav stray second tab there
    $t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    if (-not $t2) { J 'NO TAB AT ALL'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
    Invoke-CdpCmd -WsUrl $t2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "location.assign('https://signin.ea.com/p/juno/login')"; returnByValue = $true } -Id 550 | Out-Null
    Start-Sleep -Seconds 6
    $tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'juno/login' }) | Select-Object -First 1
    if (-not $t2) { J 'LOGIN TAB VANISHED'; 'LOST' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
}
$ws2 = $t2.webSocketDebuggerUrl
J ('ON ' + $t2.url.Substring(0, [Math]::Min(85, $t2.url.Length)))

# wait for render
$census = ''
for ($i = 1; $i -le 8; $i++) {
    $cf = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({n:document.querySelectorAll('input:not([type=hidden])').length,links:[].map.call(document.querySelectorAll('a,button'),function(e){if(!(e.offsetWidth||e.offsetHeight))return null;return (e.innerText||e.value||'').replace(/\s+/g,' ').trim().slice(0,22)+'#'+(e.id||'-');}).filter(Boolean).slice(0,12),ins:[].map.call(document.querySelectorAll('input:not([type=hidden])'),function(e){return (e.id||e.name||'-')+'/'+e.type;}).slice(0,8)})";
        returnByValue = $true } -Id (551 + $i)
    $cv = ''; if ($cf -and $cf.result -and $cf.result.result) { $cv = [string]$cf.result.result.value }
    J ("render$i $cv")
    $census = $cv
    if ($cv -match '"n":[2-9]') { break }
    Start-Sleep -Seconds 2
}

# ANCHOR_FILL_LOGIN
$doLogin = @'
(function(){
  function fs(el,v){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v);['keydown','keypress','input','keyup','change'].forEach(function(t){
    el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});}
  var em=document.querySelector('input[type=email],#email,input[name=email]');
  var pw=document.querySelector('input[type=password]');
  if(!em||!pw) return 'FLD-MISSING';
  fs(em,'ea499064xz@euploading.com'); fs(pw,'6&Fjd5H@4hbzy5x7');
  var btn=null;var bs=document.querySelectorAll('button,input[type=submit],[role=button]');
  for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||bs[i].value||'').replace(/\s+/g,' ').trim();
    if(/log ?in|sign ?in/i.test(t)&&(bs[i].offsetWidth||bs[i].offsetHeight)){btn=bs[i];break;}}
  if(btn){btn.click();return 'LOGIN-CLICK';}
  var fm=em.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'LOGIN-RS';}catch(e){}}
  return 'NOBTN';
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $doLogin; returnByValue = $true } -Id 560
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('LOGIN ' + $v1)

# observe post-login (20s window)
$verdict = 'UNKNOWN'
for ($i = 1; $i -le 6; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -match 'juno/login' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    J ("obs$i " + $u.Substring(0, [Math]::Min(80, $u.Length)))
    if ($u -notmatch 'juno/login') { $verdict = 'LOGIN-SUCCESS-LEFT-PAGE'; break }
    # in-page signals: error text vs session UI
    $sig = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({err:[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){if(e.offsetParent)return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,60);}).filter(Boolean).slice(0,3),heads:[].map.call(document.querySelectorAll('h1,h2'),function(e){return (e.innerText||'').trim().slice(0,40);}).slice(0,3)})";
        returnByValue = $true } -Id (565 + $i)
    $sv = ''; if ($sig -and $sig.result -and $sig.result.result) { $sv = [string]$sig.result.result.value }
    J ("sig$i " + $sv)
    if ($sv -match 'invalid|incorrect|not found|no account|mismatch') { $verdict = 'LOGIN-FAILED-CREDENTIALS'; break }
}
if ($verdict -eq 'UNKNOWN') {
    # maybe still on login page with no errors - but let us verify who am-i via pid check
    $verdict = 'LOGIN-STAGED-UNCLEAR'
}
$verdict | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $verdict")

$s = Invoke-CdpCmd -WsUrl $ws2 -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 575
if ($s -and $s.result -and $s.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_t110_shot.jpg'), [Convert]::FromBase64String($s.result.data))
    J 'SHOT SAVED'
}
J '=== DONE'

