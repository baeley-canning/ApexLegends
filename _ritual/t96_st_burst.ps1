# t96_st_burst.ps1 - fresh id + instant click inside the 2s enable window; rapid netlog drain.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t96_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== BURST'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$tail = -join ((1..3) | ForEach-Object { 'abcdefghjkmnpqrstuvwxyz23456789'[(Get-Random -Maximum 33)] })
$id = 'qaz' + $tail          # brand-new namespace, 12 chars
$pw = '6&Fjd5H@4hbzy5x7'     # proven-clean password from t93
J ("FRESHID $id")

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl

# type -> read btn class -> INSTANT conditional click, all in ONE evaluate (sub-ms latency)
$burst = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  window.__netlog=[];
  var of=window.fetch;
  window.fetch=function(){var u=(arguments[0]&&(arguments[0].url||arguments[0]))+'';
    var rec={u:u.slice(0,120)};window.__netlog.push(rec);
    return of.apply(this,arguments).then(function(r){rec.s=r.status;return r;});};
  var proto=window.HTMLInputElement.prototype;
  var dsc=Object.getOwnPropertyDescriptor(proto,'value');
  function typeInto(el,text){
    dsc.set.call(el,'');el.dispatchEvent(new Event('input',{bubbles:true}));
    el.focus();
    for(var i=0;i<text.length;i++){var ch=text.charAt(i);
      el.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true,cancelable:true}));
      el.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true,cancelable:true}));
      dsc.set.call(el,el.value+ch);
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true,cancelable:true}));}
    el.dispatchEvent(new Event('change',{bubbles:true}));el.blur();}
  var idEl=document.getElementById('originId');
  var pwEl=document.querySelector('input[type=password]');
  if(!idEl||!pwEl) return 'MISSINGFIELDS';
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=document.getElementById('readAccept');
  if(chk&&!chk.checked){chk.click();}
  // read button class NOW
  var btn=null,cls='';
  var bs=document.querySelectorAll('button,a,[role=button],wf-button');
  for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){btn=bs[i];cls=bs[i].className||'';break;}}
  var locked=cls.indexOf('disabled')>=0;
  var out={clsAtNow:cls.slice(0,80),locked:locked};
  if(btn&&!locked){btn.click();out.clicked=true;}
  return JSON.stringify(out);
})()
'@
$burst = $burst.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $burst; returnByValue = $true } -Id 181
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('BURST ' + $v1)

# rapid nav + netlog sampling, tight loop to fit worker lifespan
for ($i = 1; $i -le 7; $i++) {
    Start-Sleep -Milliseconds 2500
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    $short = if ($u.Length -gt 60) { $u.Substring(0, 60) } else { $u }
    $fn = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({n:(window.__netlog||[]).length,first:JSON.stringify((window.__netlog||[])[0]||null)})";
        returnByValue = $true } -Id (190 + $i)
    $vn = ''; if ($fn -and $fn.result -and $fn.result.result) { $vn = [string]$fn.result.result.value }
    J ("t$i $short NET $vn")
    if ($u -notmatch '/p/juno/create') { J 'NAVIGATED-OUT'; break }
}

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $s2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 199
    if ($s2 -and $s2.result -and $s2.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t96_shot.jpg'), [Convert]::FromBase64String($s2.result.data))
        J 'SHOT SAVED'
    }
    if ($pg2.url -notmatch '/p/juno/create') {
        $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); finalUrl = $pg2.url }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        J '=== ARCHIVED ok=True'
    } else { J '=== STILL S4 ok=False' }
}
