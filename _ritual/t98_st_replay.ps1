# t98_st_replay.ps1 - fresh GET of s4 (flow resume), full dump, hook, resubmit, watch render.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t98_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== REPLAY'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$id = 'ea499064xzacs'
$pw = '6&Fjd5H@4hbzy5x7'

$pg0 = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg0) { J 'NO PAGE'; exit 1 }
$ws = $pg0.webSocketDebuggerUrl
$u0 = $pg0.url.Substring(0, 4000)
Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
    expression = "location.assign('" + ($u0 -replace "'", '') + "')"; returnByValue = $true } -Id 231 | Out-Null
J 'NAV SENT'
Start-Sleep -Seconds 6

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'PAGE LOST'; exit 1 }
J ('NOW ' + $pg.url.Substring(0, 90))
$ws = $pg.webSocketDebuggerUrl

# post-reload dump
$dump = @'
(function(){
  var rows=[];
  [].forEach.call(document.querySelectorAll('input,textarea,select,button,a,wf-button'),
    function(el){ if(!(el.offsetWidth||el.offsetHeight))return;
      rows.push(el.tagName+'#'+(el.id||'-')+'.'+(el.type||'')+'='+
        (el.type==='checkbox'?el.checked:(el.value||'').slice(0,30))+
        '|'+((el.className||'')+'').slice(0,30)+'|ai:'+(el.getAttribute('aria-invalid')||'-'));});
  var hdgs=[];
  [].forEach.call(document.querySelectorAll('h1,h2,h3,label,.otktitle'),
    function(el){var t=(el.innerText||'').replace(/\s+/g,' ').trim();if(t)hdgs.push(t.slice(0,50));});
  var fm=document.querySelector('form');
  var fmeta=fm?{a:fm.action.slice(0,110),m:fm.method||'-'}:null;
  return JSON.stringify({inputs:rows.slice(0,24),heads:hdgs.slice(0,8),form:fmeta});
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $dump; returnByValue = $true } -Id 232
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('POSTLOAD ' + $v1)

# hook + fill + click
$fill = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  window.__netlog=[];
  var os=XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open=function(m,u){this.__r={m:m,u:(u+'').slice(0,140)};window.__netlog.push(this.__r);
    this.addEventListener('load',function(){this.__r.s=this.status;
      try{this.__r.b=(this.response||this.responseText||'').toString().slice(0,400);}catch(e){}});
    return os.apply(this,arguments);};
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
  var pwEl=document.querySelector('input[type=password]');
  if(!idEl||!pwEl) return 'MISSING';
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=document.getElementById('readAccept');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  var btn=null,cls='';
  var bs=document.querySelectorAll('button,a,[role=button],wf-button');
  for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){btn=bs[i];cls=bs[i].className||'';break;}}
  var locked=cls.indexOf('disabled')>=0,out={cls:cls.slice(0,60),locked:locked};
  if(btn){btn.click();out.via=locked?'D_blind':'A';}
  return JSON.stringify(out);
})()
'@
$fill = $fill.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f2 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $fill; returnByValue = $true } -Id 233
$v2 = '?'; if ($f2 -and $f2.result -and $f2.result.result) { $v2 = [string]$f2.result.result.value }
J ('FILLCLK ' + $v2)

# watch nets
for ($i = 1; $i -le 4; $i++) {
    Start-Sleep -Milliseconds 2700
    $fn = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify((window.__netlog||[]).slice(0,4))"; returnByValue = $true } -Id (240 + $i)
    $vn = ''; if ($fn -and $fn.result -and $fn.result.result) { $vn = [string]$fn.result.result.value }
    J ("net$i " + $vn)
}

$f3 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
    expression = "JSON.stringify({href:location.href.slice(0,110),ttl:document.title,errs:[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){return (e.innerText||'').replace(/\\s+/g,' ').trim();}).filter(Boolean).slice(0,8)})";
    returnByValue = $true } -Id 245
if ($f3 -and $f3.result -and $f3.result.result) { J ('AFTER ' + [string]$f3.result.result.value) }

$s = Invoke-CdpCmd -WsUrl $ws -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 246
if ($s -and $s.result -and $s.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_t98_shot.jpg'), [Convert]::FromBase64String($s.result.data))
    J 'SHOT SAVED'
}
J '=== DONE'
