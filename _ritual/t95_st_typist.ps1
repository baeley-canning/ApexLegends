# t95_st_typist.ps1 - humanized per-char typing with focus/blur arcs; wait for button enable; click.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t95_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== TYPIST'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$s = @('ea499064xzacs', '6&Fjd5H@4hbzy5x7')  # t93/t94-verified pair, keep constant this probe
$id = $s[0]; $pw = $s[1]

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl

$typeJs = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  window.__netlog=window.__netlog||[];
  function kd(k){return new KeyboardEvent('keydown',{key:k,bubbles:true,cancelable:true});}
  function kp(k){return new KeyboardEvent('keypress',{key:k,bubbles:true,cancelable:true});}
  function ku(k){return new KeyboardEvent('keyup',{key:k,bubbles:true,cancelable:true});}
  var proto=window.HTMLInputElement.prototype;
  var dsc=Object.getOwnPropertyDescriptor(proto,'value');
  function typeInto(el,text){
    dsc.set.call(el,'');
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.focus(); el.dispatchEvent(new FocusEvent('focus',{bubbles:false}));
    for(var i=0;i<text.length;i++){
      var ch=text.charAt(i);
      el.dispatchEvent(kd(ch)); el.dispatchEvent(kp(ch));
      dsc.set.call(el, el.value+ch);
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(ku(ch));
    }
    el.dispatchEvent(new Event('change',{bubbles:true}));
    el.blur(); el.dispatchEvent(new FocusEvent('blur',{bubbles:false}));
  }
  var idEl=document.getElementById('originId');
  var pwEl=document.querySelector('input[type=password]');
  if(!idEl||!pwEl) return JSON.stringify({err:'missing '+(idEl?'':'id ')+(pwEl?'':'pw')});
  typeInto(idEl, eaId);
  setTimeout(function(){},0);
  typeInto(pwEl, pass);
  var chk=document.getElementById('readAccept');
  if(chk&&!chk.checked){ chk.focus(); chk.click(); chk.blur(); }
  var btn=null,cls='';
  var bs=document.querySelectorAll('button,a,[role=button],wf-button');
  for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){btn=bs[i];cls=bs[i].className;break;}}
  return JSON.stringify({typed:[idEl.value,pwEl.value.length],
    chk:chk?chk.checked:null,btnCls:cls?cls.slice(0,90):'?'});
})()
'@
$typeJs = $typeJs.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $typeJs; returnByValue = $true } -Id 141
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('TYPED ' + $v1)

# poll for the disabled class to lift (async availability check allowance)
$enabled = $false
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 2
    $poll = @'
(function(){
  var bs=document.querySelectorAll('button,a,[role=button],wf-button');
  for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){
      var c=bs[i].className||'';
      return JSON.stringify({dis:c.indexOf('disabled')>=0,cls:c.slice(0,90),
        errs:(function(){var e=document.querySelector('[class*=error]');return e&&e.offsetParent?e.innerText.replace(/\s+/g,' ').trim():'';})()});}}
  return JSON.stringify({dis:'nobtn'});})()
'@
    $fp = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $poll; returnByValue = $true } -Id (150 + $i)
    $vp = '?'; if ($fp -and $fp.result -and $fp.result.result) { $vp = [string]$fp.result.result.value }
    J ("poll $i " + $vp)
    if ($vp -match '"dis":false') { $enabled = $true; break }
    if ($vp -match 'nobtn') { break }
}

if ($enabled) {
    J 'BUTTON LIVE - CLICKING'
    $ck = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "(function(){var bs=document.querySelectorAll('button,a,[role=button],wf-button');for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){bs[i].click();return 'SENTHOME';}}return 'NOBTN';})()";
        returnByValue = $true } -Id 160
    J ('CLICK ' + $(if ($ck -and $ck.result) { [string]$ck.result.result.value } else { '?' }))
} else { J 'BUTTON STAYED LOCKED' }

# observe: nav + netlog
$left = $false
for ($i = 1; $i -le 6; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    J ("nav $i " + $u.Substring(0, [Math]::Min(70, $u.Length)))
    if ($u -notmatch '/p/juno/create') { $left = $true; break }
}
$f3 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
    expression = "JSON.stringify((window.__netlog||[]).slice(0,8))"; returnByValue = $true } -Id 170
if ($f3 -and $f3.result -and $f3.result.result) { J ('NETLOG ' + [string]$f3.result.result.value) }

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $s2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 171
    if ($s2 -and $s2.result -and $s2.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t95_shot.jpg'), [Convert]::FromBase64String($s2.result.data))
        J 'SHOT SAVED'
    }
}
if ($left -and $pg2) {
    $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); finalUrl = $pg2.url }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J '=== ARCHIVED ok=True'
} else { J '=== STILL DOWN ok=False' }
