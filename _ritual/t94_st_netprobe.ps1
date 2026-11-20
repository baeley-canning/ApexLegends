# t94_st_netprobe.ps1 - instrument browser network layer, click CREATE, drain capture.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t94_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== NETPROBE'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl

# 1. install hooks + validity audit (no mutation)
$install = @'
(function(){
  if(!window.__netlog){
    window.__netlog=[];
    var of=window.fetch;
    window.fetch=function(){
      var u=(arguments[0]&&(arguments[0].url||arguments[0]))+'';
      var rec={t:Date.now(),kind:'fetch',url:u.slice(0,140)};
      window.__netlog.push(rec);
      var pr=of.apply(this,arguments);
      pr.then(function(r){rec.status=r.status;});
      return pr;
    };
    var os=XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open=function(m,u){
      this.__rec={t:Date.now(),kind:'xhr',method:m,url:(u+'').slice(0,140)};
      window.__netlog.push(this.__rec);
      this.addEventListener('load',function(){this.__rec.status=this.status;
        try{this.__rec.snip=(this.responseText||'').slice(0,300);}catch(e){}});
      return os.apply(this,arguments);
    };
  }
  var fm=document.querySelector('form');
  var btn=null,btnDisabled=null;
  var bs=document.querySelectorAll('button,[role=button],wf-button');
  for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){btn=bs[i];break;}}
  var vals={};
  [].forEach.call(document.querySelectorAll('input:not([type=hidden])'),function(x){
    if(x.offsetWidth||x.offsetHeight) vals[(x.id||x.name||x.type)]=
      (x.type==='checkbox')?x.checked:x.value; });
  return JSON.stringify({hooks:'installed',
    formAction:fm?fm.action.slice(0,110):'NOFORM',
    formValid:fm?fm.checkValidity():null,
    btnFound:!!btn, btnDisabled:btn?btn.disabled:null,
    btnCls:btn?btn.className.slice(0,80):'',
    fieldVals:vals});
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $install; returnByValue = $true } -Id 121
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('SETUP ' + $v1)

# 2. click
$clickJs = "(function(){var bs=document.querySelectorAll('button,[role=button],wf-button');for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){bs[i].click();return 'CLICKED';}}return 'NOBTN';})()"
$f2 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $clickJs; returnByValue = $true } -Id 122
J ('CLICK ' + $(if ($f2 -and $f2.result) { [string]$f2.result.result.value } else { '?' }))

# 3. drain captures at intervals
for ($i = 1; $i -le 4; $i++) {
    Start-Sleep -Seconds 4
    $drain = "JSON.stringify(window.__netlog||[])"
    $f3 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $drain; returnByValue = $true } -Id (130 + $i)
    if ($f3 -and $f3.result -and $f3.result.result) { J ("NET$i " + [string]$f3.result.result.value) }
}

# 4. location + page-level errors snapshot
$f4 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
    expression = "JSON.stringify({href:location.href.slice(0,110),title:document.title})"; returnByValue = $true } -Id 135
if ($f4 -and $f4.result -and $f4.result.result) { J ('LOC ' + [string]$f4.result.result.value) }

$s = Invoke-CdpCmd -WsUrl $ws -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 136
if ($s -and $s.result -and $s.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_t94_shot.jpg'), [Convert]::FromBase64String($s.result.data))
    J 'SHOT SAVED'
}
J '=== DONE'
