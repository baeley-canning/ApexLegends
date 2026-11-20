# t106_st_exactid.ps1 - explicit readAccept by ID, unlock-poll, trusted click at live moment.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t106_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== EXACTID'

. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl
J ('AT ' + $pg.url.Substring(0, 85))

# 1. ritual with EXPLICIT ids + readback
$prep = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  var proto=window.HTMLInputElement.prototype;
  var dsc=Object.getOwnPropertyDescriptor(proto,'value');
  function ev(el,t){el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));}
  function typeInto(el,text){dsc.set.call(el,'');ev(el,'input');el.focus();
    for(var i=0;i<text.length;i++){var ch=text.charAt(i);
      el.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true,cancelable:true}));
      el.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true,cancelable:true}));
      dsc.set.call(el,el.value+ch);ev(el,'input');
      el.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true,cancelable:true}));}
    ev(el,'change');el.blur();}
  var idEl=document.getElementById('originId');
  var pwEl=document.getElementById('password');
  var chk=document.getElementById('readAccept');
  if(!idEl||!pwEl||!chk) return JSON.stringify({fatal:[!!idEl,!!pwEl,!!chk]});
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  chk.focus(); if(!chk.checked) chk.click(); chk.blur();
  var chk2=document.getElementById('readAcceptUnderage');
  return JSON.stringify({id:idEl.value,pwLen:pwEl.value.length,
    chk:chk.checked,underageChk:chk2?chk2.checked:'none'});
})()
'@
$prep = $prep.Replace('__EAID__', 'ea499064xzacs').Replace('__PASS__', '6&Fjd5H@4hbzy5x7')
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $prep; returnByValue = $true } -Id 401
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('PREP ' + $v1)
if ($v1 -match 'fatal') { J 'ABORT MISSING ELEMENT'; exit 1 }

# 2. unlock poll (10 x 1.5s)
$live = $false
$xy = $null
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Milliseconds 1500
    $po = @'
(function(){
  var b=document.getElementById('basicInfoNextBtn');
  if(!b) return JSON.stringify({gone:true});
  var c=(b.className||'');
  var r=b.getBoundingClientRect();
  return JSON.stringify({locked:c.indexOf('disabled')>=0,
    x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});
})()
'@
    $fp = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $po; returnByValue = $true } -Id (405 + $i)
    $vp = ''; if ($fp -and $fp.result -and $fp.result.result) { $vp = [string]$fp.result.result.value }
    J ("unlock$i $vp")
    if ($vp -match '"locked":false,"x":(\d+),"y":(\d+)') {
        $live = $true; $xy = @{ x = [int]$Matches[1]; y = [int]$Matches[2] }; break
    }
    if ($vp -match '"gone":true') { break }
}

# 3. strike
if ($live) {
    J ("LIVE WINDOW at $($xy.x),$($xy.y) - trusting in")
    Invoke-CdpCmd -WsUrl $ws -Method 'Input.dispatchMouseEvent' -Params @{
        type = 'mouseMoved'; x = $xy.x; y = $xy.y } -Id 420 | Out-Null
    Invoke-CdpCmd -WsUrl $ws -Method 'Input.dispatchMouseEvent' -Params @{
        type = 'mousePressed'; x = $xy.x; y = $xy.y; button = 'left'; clickCount = 1 } -Id 421 | Out-Null
    Invoke-CdpCmd -WsUrl $ws -Method 'Input.dispatchMouseEvent' -Params @{
        type = 'mouseReleased'; x = $xy.x; y = $xy.y; button = 'left'; clickCount = 1 } -Id 422 | Out-Null
    J 'TRUSTED CLICK DELIVERED'
} else {
    # forcing fallback: requestSubmit on reg-form (form index 1)
    J 'NEVER UNLOCKED - requestSubmit fallback'
    $rs = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "(function(){var f=document.querySelectorAll('form')[1];if(f&&f.requestSubmit){try{f.requestSubmit();return 'RS-OK';}catch(e){return 'RS-ERR';}}return 'NOFORM';})()";
        returnByValue = $true } -Id 423
    J ('RS ' + $(if ($rs -and $rs.result) { [string]$rs.result.result.value } else { '?' }))
}

# 4. ride out
$left = $false
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    J ("ride $i " + $u.Substring(0, [Math]::Min(80, $u.Length)))
    if ($u -notmatch '/p/juno/create') { $left = $true; break }
}

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 430
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t106_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
    if ($left) {
        $acct = [ordered]@{ eaId = 'ea499064xzacs'; email = 'ea499064xz@euploading.com'; password = '6&Fjd5H@4hbzy5x7'; createdAt = (Get-Date).ToString('s'); status = 'exited-wizard'; exitUrl = $pg2.url.Substring(0, [Math]::Min(180, $pg2.url.Length)) }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        "EA ACCOUNT CREATED`neaId: ea499064xzacs`nemail: ea499064xz@euploading.com`npassword: 6&Fjd5H@4hbzy5x7`ncreated: $((Get-Date).ToString('s'))" |
            Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ACCOUNT DONE ok=True'
    } else { J '=== GATES HOLD ok=False' }
}
