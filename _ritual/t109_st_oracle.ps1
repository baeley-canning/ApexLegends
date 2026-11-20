# t109_st_oracle.ps1 - second-tab forgot-password probe: reset-mail arrival = account exists.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t109_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== ORACLE'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }
. (Join-Path $here '_cdp.ps1')

# baseline: current ledger + newest message id
$m0 = Get-T88-Mail $hdr
$baselineId = if ($m0) { $m0.id } else { '' }
J ("BASELINE msg=$baselineId")

# 1. open tab2 on the login page (GET first, PUT fallback)
$lurl = 'http://127.0.0.1:9333/json/new?url=' + [uri]::EscapeDataString('https://signin.ea.com/p/juno/login')
try { Invoke-RestMethod -Uri $lurl -Method Get -TimeoutSec 8 | Out-Null; J 'TAB GET ok' }
catch {
    try {
        Add-Type -AssemblyName System.Net.Http
        $hc = New-Object System.Net.Http.HttpClient
        $resp = $hc.PutAsync($lurl, $null); $resp.Wait(8000) | Out-Null
        J 'TAB PUT tried'
    } catch { J ('TAB OPEN ERR2 ' + $_.Exception.Message) }
}
Start-Sleep -Seconds 6

# discover tab2 (anything except the wizard tab)
$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$pages = @($tabs | Where-Object { $_.type -eq 'page' })
J ("TABS " + $pages.Count)
$t2 = @($pages | Where-Object { $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO SECOND TAB'; exit 1 }
J ('RAW2 ' + $t2.url.Substring(0, [Math]::Min(85, $t2.url.Length)))
# force it onto the login page if it drifted
if ($t2.url -notmatch 'signin\.ea\.com') {
    Invoke-CdpCmd -WsUrl $t2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "location.assign('https://signin.ea.com/p/juno/login')"; returnByValue = $true } -Id 528 | Out-Null
    Start-Sleep -Seconds 7
    $tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    if (-not $t2) { J 'TAB2 DRIFT LOST'; exit 1 }
}
$ws2 = $t2.webSocketDebuggerUrl
J ('TAB2 ' + $t2.url.Substring(0, 80))

# 2. census of login page (find forgot link + email field)
$cen = @'
(function(){
  var links=[].map.call(document.querySelectorAll('a,button'),function(e){
    if(!(e.offsetWidth||e.offsetHeight))return null;
    var t=(e.innerText||'').replace(/\s+/g,' ').trim();
    return t?t.slice(0,30)+'|'+(e.id||'-')+'|'+(e.href||'').slice(-40):null;}).filter(Boolean).slice(0,15);
  var ins=[].map.call(document.querySelectorAll('input:not([type=hidden])'),function(e){
    return (e.id||'-')+'/'+e.type;}).slice(0,10);
  return JSON.stringify({links:links,inputs:ins});
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $cen; returnByValue = $true } -Id 530
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('LOGINPG ' + $v1)

# 3. click Forgot your password? (id/text flexible)
$forgot = @'
(function(){
  var cand=document.querySelectorAll('a,button,[role=link]');
  for(var i=0;i<cand.length;i++){
    var t=(cand[i].innerText||'').replace(/\s+/g,' ');
    if(/forgot/i.test(t)&&(cand[i].offsetWidth||cand[i].offsetHeight)){cand[i].click();return 'FORGOT-'+t.slice(0,25);}
  }
  // direct href probe
  var a=document.querySelector('a[href*="reset"],a[href*="forgot"]');
  if(a){return 'HREF:'+a.href.slice(-45);}
  return 'NOTFOUND';
})()
'@
$f2 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $forgot; returnByValue = $true } -Id 531
$v2 = '?'; if ($f2 -and $f2.result -and $f2.result.result) { $v2 = [string]$f2.result.result.value }
J ('FORGOT ' + $v2)
Start-Sleep -Seconds 5

# refresh tab info (may have navigated)
$t2b = Get-CdpPage -Port 9333 -Match 'ea.com/signup|juno/login|juno/reset|forgot'
if (-not $t2b) { $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'; $t2b = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1 }
if (-not $t2b) { J 'TAB2 LOST'; exit 1 }
$ws2 = $t2b.webSocketDebuggerUrl
J ('NOW2 ' + $t2b.url.Substring(0, [Math]::Min(85, $t2b.url.Length)))

# 4. on reset page: fill email + submit
$doReset = @'
(function(){
  var em=document.querySelector('input[type=email],#email,input[name=email],input[id*=email]');
  if(!em) return 'NOEMAILFIELD';
  var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
  st.call(em,'__MAIL__');
  ['keydown','keypress','input','keyup','change'].forEach(function(t){
    em.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});
  em.blur();
  var btns=document.querySelectorAll('button,[role=button],input[type=submit],a');
  for(var i=0;i<btns.length;i++){
    var t=(btns[i].value||btns[i].innerText||'').replace(/\s+/g,' ').trim();
    if(/^(send|submit|next|reset|continue)/i.test(t)&&(btns[i].offsetWidth||btns[i].offsetHeight)){
      if((btns[i].className||'').indexOf('disabled')>=0) return 'BTNLOCKED:'+t;
      btns[i].click(); return 'RESETBTN:'+t.slice(0,20);
    }
  }
  var fm=em.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS-RESET';}catch(e){}}
  return 'NOBTN';
})()
'@
$doReset = $doReset.Replace('__MAIL__', $mail.address)
$f3 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $doReset; returnByValue = $true } -Id 532
$v3 = '?'; if ($f3 -and $f3.result -and $f3.result.result) { $v3 = [string]$f3.result.result.value }
J ('RESETACT ' + $v3)

# 5. poll inbox 45s for a message newer than baseline with reset-ish subject
$verdict = 'TIMEOUT-UNKNOWN'
for ($i = 1; $i -le 9; $i++) {
    Start-Sleep -Seconds 5
    try {
        $mm = Get-T88-Mail $hdr
        if ($mm -and $mm.id -ne $baselineId) {
            $subj = $mm.subject
            J ('NEWMAIL ' + $subj)
            $verdict = 'ACCOUNT-EXISTS'
            if ($subj -match 'reset|password') { $verdict = 'ACCOUNT-EXISTS-RESETMAIL' }
            break
        }
    } catch { J ("poll err $i") }
}
J ("VERDICT $verdict")
"$verdict" | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')

# leave tab2 open for eyeballing; snapshot
$s = Invoke-CdpCmd -WsUrl $ws2 -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 540
if ($s -and $s.result -and $s.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_t109_shot.jpg'), [Convert]::FromBase64String($s.result.data))
    J 'SHOT SAVED'
}
J '=== DONE'

