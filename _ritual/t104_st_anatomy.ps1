# t104_st_anatomy.ps1 - full form/button census, page text, scoped-reg-form submit, perf-entry trap.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t104_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== ANATOMY'

. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl

# ---- 1. census ----
$cen = @'
(function(){
  var fs=[].map.call(document.querySelectorAll('form'),function(f,i){
    var hid={};[].forEach.call(f.querySelectorAll('input[type=hidden]'),function(h){
      if(h.name)hid[h.name]=(h.value||'').slice(0,30);});
    return {i:i,actionTail:f.action.split('?')[1]?f.action.split('?')[1].slice(0,30):f.action.slice(-30),
      m:f.method,ids:[].map.call(f.querySelectorAll('input:not([type=hidden])'),function(x){return x.id||x.name||x.type;}),
      hid:hid,containsBtn:f.querySelector('button,[class*=otkbtn],[role=button]')?'Y':'N'};
  });
  var ctls=[].map.call(document.querySelectorAll('a,[role=button],wf-button,[class*=otkbtn],div[class*=btn],span[class*=btn]'),
    function(e){ if(!(e.offsetWidth||e.offsetHeight))return null;
      var t=(e.innerText||'').replace(/\s+/g,' ').trim();
      return t?t.slice(0,22)+'|'+(e.id||'-')+'|'+((e.className||'')+'').split(' ')[0]+'|form:'+(e.closest('form')?Array.prototype.indexOf.call(document.querySelectorAll('form'),e.closest('form')):'-'):null;})
    .filter(Boolean).slice(0,14);
  var txt=(document.body.innerText||'').replace(/\s+/g,' ').trim().slice(0,700);
  return JSON.stringify({forms:fs,ctls:ctls,txt:txt});
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $cen; returnByValue = $true } -Id 371
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('CENSUS ' + $v1)

# ---- 2. perf trap install + scoped ritual submit ----
$id = 'ea499064xzacs'
$pw = '6&Fjd5H@4hbzy5x7'
$strike = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  window.__perf=[]; window.__xhr=[];
  try{
    var po=new PerformanceObserver(function(l){
      l.getEntries().forEach(function(e){
        if(e.entryType==='resource'||e.entryType==='navigation')
          window.__perf.push({n:(e.name||'').slice(-60),s:e.responseStatus||0,
            ini:(e.initiatorType||'').slice(0,8),d:Math.round(e.duration||0)});
      });
    });
    po.observe({entryTypes:['resource','navigation']});
  }catch(e){}
  var os=XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open=function(m,u){this.__r={m:m,u:(u+'').slice(-70)};window.__xhr.push(this.__r);
    this.addEventListener('load',function(){this.__r.s=this.status;
      try{this.__r.b=(this.response||this.responseText||'').toString().slice(0,350);}catch(e){}});
    return os.apply(this,arguments);};
  var forms=document.querySelectorAll('form');
  var reg=null; // pick the form that contains a text input used for the EA ID or password
  for(var i=0;i<forms.length;i++){
    if(forms[i].querySelector('input[type=password],input[id*=origin],input[id*=eaid]')){reg=forms[i];break;}
  }
  if(!reg) reg=(function(){var best=null;for(var i=0;i<forms.length;i++){var n=forms[i].querySelectorAll('input:not([type=hidden])').length;if(n>1&&!best)best=forms[i];}return best;})();
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
  var tgt=[].filter.call(reg.querySelectorAll('input'),function(x){return !x.type||x.type!=='hidden';});
  var idEl=reg.querySelector('input[id*=origin]')||tgt[0];
  var pwEl=reg.querySelector('input[type=password]')||tgt[1];
  if(!idEl||!pwEl) return JSON.stringify({fatal:'miss',scope:reg.id||reg.action.slice(-25),
    tgt:tgt.map(function(x){return x.id+'/'+x.type;})});
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=reg.querySelector('input[type=checkbox]')||document.getElementById('readAccept');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  // button inside this form
  var btn=reg.querySelector('button,[role=button],[class*=otkbtn]');
  var via='',cls='';
  if(btn){cls=(btn.className||'').slice(0,50);var lk=cls.indexOf('disabled')>=0;
    btn.click();via=lk?'blind':'live';}
  if(!via||via==='blind'){
    try{ reg.requestSubmit(); via+=' +RS'; }catch(e){ via+=' rsErr'; }
  }
  return JSON.stringify({via:via,scope:(reg.id||reg.action.split('?')[1]||'').slice(0,25),
    cls:cls,fcount:forms.length,btnTag:btn?btn.tagName:'-'});
})()
'@
$strike = $strike.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f2 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $strike; returnByValue = $true } -Id 372
$v2 = '?'; if ($f2 -and $f2.result -and $f2.result.result) { $v2 = [string]$f2.result.result.value }
J ('STRIKE ' + $v2)

# ---- 3. settle + autopsy ----
Start-Sleep -Seconds 7
$aut = @'
(function(){
  var pf=(window.__perf||[]).filter(function(e){return e.ini!=='xmlhttprequest';}).slice(0,10);
  var xr=(window.__xhr||[]).slice(0,6);
  return JSON.stringify({perf:pf,xhr:xr,now:location.href.match(/execution[^&]*/)[0]});
})()
'@
$f3 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $aut; returnByValue = $true } -Id 373
$v3 = '?'; if ($f3 -and $f3.result -and $f3.result.result) { $v3 = [string]$f3.result.result.value }
J ('AUTOPSY ' + $v3)

$s = Invoke-CdpCmd -WsUrl $ws -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 374
if ($s -and $s.result -and $s.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_t104_shot.jpg'), [Convert]::FromBase64String($s.result.data))
    J 'SHOT SAVED'
}
J '=== DONE'

