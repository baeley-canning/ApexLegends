# t85_st_fill2.ps1 - harvest step-2 page; if it holds email/password fields, fill them + continue; harvest step-3.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t85_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== STEP2 FILL'

. (Join-Path $here '_cdp.ps1')

function Save-Harvest($idSuffix, $domFile, $imgFile) {
    $p = Get-CdpPage -Port 9333 -Match 'ea.com'
    if (-not $p) { $p = Get-CdpPage -Port 9333 -Index 1 }
    if (-not $p) { J 'NO PAGE'; return $null }
    $js = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $fr = Invoke-CdpCmd -WsUrl $p.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $js; returnByValue = $true } -Id $idSuffix
    if ($fr -and $fr.result -and $fr.result.result) {
        ([string]$fr.result.result.value) | Out-File -Encoding utf8 (Join-Path $here $domFile)
        J ('DOM ' + $domFile)
    }
    $sc = Invoke-CdpCmd -WsUrl $p.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id ($idSuffix + 100)
    if ($sc -and $sc.result -and $sc.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here $imgFile), [Convert]::FromBase64String($sc.result.data))
        J ('IMG ' + $imgFile)
    }
    return $p
}

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
J ('IDENTITY ' + $mail.address)

$p1 = Save-Harvest 31 '_dom4_step2.txt' '_t85_step2.jpg'
if (-not $p1) { exit 1 }
J ('PAGE1 ' + $p1.url)

# fill step2 if email-ish
$fill2 = @'
(function(){
  var mail = '__MAIL__', pass = '__PASS__';
  function fire(e){ ['input','change'].forEach(function(t){
    e.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  var setCount = 0, metas=[];
  var ins = document.querySelectorAll('input:not([type=hidden])');
  for (var i=0;i<ins.length;i++){
    var e = ins[i]; if (!(e.offsetWidth||e.offsetHeight)) continue;
    var sig = ((e.id||'')+' '+(e.name||'')+' '+(e.type||'')).toLowerCase();
    if (e.type==='checkbox'){ continue; }
    var v = '';
    if (/pass/.test(sig)) v = pass;
    else if (e.tagName==='INPUT' && (/(mail)/.test(sig)||e.type==='email'||/phone/.test(sig))) v = mail;
    if (v){
      var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
      setter.call(e, v); fire(e);
      metas.push(e.id+':'+e.type); setCount++;
    }
  }
  // find continue/next
  var nx=null; var bs=document.querySelectorAll('button, [role=button], wf-button');
  for (var b=0;b<bs.length;b++){ var t=(bs[b].textContent||'').replace(/\s+/g,' ').trim();
    if(/^(next|continue)$/i.test(t)){ nx=bs[b]; break; } }
  var res='SET '+setCount+' ['+metas.join(',')+']';
  if(nx&&!nx.disabled){ nx.click(); res+=' CLICKED '+nx.textContent.trim(); }
  else if(nx){ res+=' DISABLED'; }
  return res;
})()
'@
$fill2 = $fill2.Replace('__MAIL__', $mail.address).Replace('__PASS__', $mail.password)
$f2 = Invoke-CdpCmd -WsUrl $p1.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $fill2; returnByValue = $true } -Id 32
$fv = '?'; if ($f2 -and $f2.result -and $f2.result.result) { $fv = [string]$f2.result.result.value }
J ('FILL2 ' + $fv)

if ($fv -match 'CLICKED') {
    Start-Sleep -Seconds 6
    $p2 = Get-CdpPage -Port 9333 -Match 'ea.com'
    if ($p2) { J ('PAGE2 ' + $p2.url) }
    Save-Harvest 41 '_dom5_step3.txt' '_t86_step3.jpg'
}
J '=== DONE'
