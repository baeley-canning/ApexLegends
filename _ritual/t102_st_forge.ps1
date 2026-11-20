# t102_st_forge.ps1 - ritual fill -> requestSubmit -> bake -> self-GET reveal -> archive-on-success.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t102_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== FORGE'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$id = 'ea499064xzacs'
$pw = '6&Fjd5H@4hbzy5x7'

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$urlNow = $pg.url
$ws = $pg.webSocketDebuggerUrl
J ('AT ' + $urlNow.Substring(0, 90))

# 1. ritual fill + immediate native submit in one tick
$forge = @'
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
  var pwEl=document.querySelector('input[type=password]');
  if(!idEl||!pwEl) return 'MISSING';
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=document.getElementById('readAccept');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  var fm=document.querySelector('form');
  if(!fm) return 'NOFORM';
  try{ fm.requestSubmit(); return 'FORGED'; }catch(e){ return 'ERR:'+(''+e).slice(0,40); }
})()
'@
$forge = $forge.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $forge; returnByValue = $true } -Id 301
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('FORGE ' + $v1)

# 2. bake
Start-Sleep -Seconds 6

# 3. self-GET reveal: navigate to the SAME url; server 302s to true state
$reveal = "location.assign('" + ($urlNow -replace "'", '').Substring(0, 4000) + "')"
$f2 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $reveal; returnByValue = $true } -Id 302 | Out-Null
J 'REVEAL-GET SENT'
Start-Sleep -Seconds 6

# 4. what does the server say we are?
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
$outside = $false
if ($pg2) {
    J ('TRUTH ' + $pg2.url.Substring(0, [Math]::Min(95, $pg2.url.Length)))
    $outside = ($pg2.url -notmatch '/p/juno/create')
    $ws2 = $pg2.webSocketDebuggerUrl
    # if still inside & yet ANOTHER EA-ID blank: try once more within this worker (ritual+C)
    if (-not $outside) {
        $audit = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
            expression = "JSON.stringify({ttl:document.title,idVal:(document.getElementById('originId')||{}).value||'-',btnCls:((document.getElementById('createAccountBtn')||document.querySelector('button[class*=otkbtn]'))||{className:'?'}).className.slice(0,50)})";
            returnByValue = $true } -Id 303
        if ($audit -and $audit.result -and $audit.result.result) { J ('AUDIT ' + [string]$audit.result.result.value) }
    }
    # aftermath errs
    $er = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify([].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){return e.offsetParent?(e.innerText||'').replace(/\\s+/g,' ').trim().slice(0,60):'';}).filter(Boolean).slice(0,6))";
        returnByValue = $true } -Id 304
    if ($er -and $er.result -and $er.result.result) { J ('ERRS ' + [string]$er.result.result.value) }

    $s = Invoke-CdpCmd -WsUrl $ws2 -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 305
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t102_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }

    if ($outside) {
        $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); status = 'exited-wizard'; exitUrl = $pg2.url.Substring(0, [Math]::Min(180, $pg2.url.Length)) }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        "EA ACCOUNT CREATED`neaId: $id`nemail: $($mail.address)`npassword: $pw`ncreated: $((Get-Date).ToString('s'))`nexit: $($pg2.url.Substring(0,[Math]::Min(120,$pg2.url.Length)))" |
            Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ACCOUNT DONE ok=True'
    } else { J '=== REVEAL PENDING ok=False' }
}
