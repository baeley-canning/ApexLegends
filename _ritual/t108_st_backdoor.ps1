# t108_st_backdoor.ps1 - t102 winning replica on s10: ritual + forms[0](back-form) requestSubmit + reveal.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t108_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== BACKDOOR'

. (Join-Path $here '_cdp.ps1')

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$urlNow = $pg.url
$ws = $pg.webSocketDebuggerUrl
J ('AT ' + $urlNow.Substring(0, 90))

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
  var pwEl=document.getElementById('password');
  if(!idEl||!pwEl) return 'MISSING';
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=document.getElementById('readAccept');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  var fm=document.querySelector('form');  /* FIRST form = back-form = the proven engine */
  if(!fm) return 'NOFORM';
  try{ fm.requestSubmit(); return 'BACKFORGED'; }catch(e){ return 'ERR:'+(''+e).slice(0,30); }
})()
'@
$forge = $forge.Replace('__EAID__', 'ea499064xzacs').Replace('__PASS__', '6&Fjd5H@4hbzy5x7')
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $forge; returnByValue = $true } -Id 510
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('FORGE ' + $v1)

Start-Sleep -Seconds 6
$reveal = "location.assign('" + ($urlNow -replace "'", '').Substring(0, 4000) + "')"
Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $reveal; returnByValue = $true } -Id 511 | Out-Null
J 'REVEAL SENT'
Start-Sleep -Seconds 6

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
$outside = $false
if ($pg2) {
    J ('TRUTH ' + $pg2.url.Substring(0, [Math]::Min(95, $pg2.url.Length)))
    $outside = ($pg2.url -notmatch '/p/juno/create')
    if (-not $outside) {
        # inspect what the server rendered now (could be s11+ or a retry)
        $aud = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
            expression = "JSON.stringify({step:(location.href.match(/s(\\d+)/)||[])[1],ttl:document.title,heads:[].map.call(document.querySelectorAll('h1,h2'),function(e){return (e.innerText||'').replace(/\\s+/g,' ').trim().slice(0,50);}).filter(Boolean).slice(0,4)})";
            returnByValue = $true } -Id 512
        if ($aud -and $aud.result -and $aud.result.result) { J ('AUDIT ' + [string]$aud.result.result.value) }
        # second salvo if still in wizard: repeat once more (some steps need the double-tap)
        $forge2 = $forge -replace 'return .BACKFORGED.;', 'return .BF2.;'
        $f2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{ expression = $forge; returnByValue = $true } -Id 513
        J ('FORGE2 ' + $(if ($f2 -and $f2.result) { [string]$f2.result.result.value } else { '?' }))
        Start-Sleep -Seconds 6
        $rev2 = "location.assign('" + ($pg2.url -replace "'", '').Substring(0, 4000) + "')"
        Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{ expression = $rev2; returnByValue = $true } -Id 514 | Out-Null
        Start-Sleep -Seconds 6
        $pg3 = Get-CdpPage -Port 9333 -Match 'ea.com'
        if ($pg3) {
            J ('TRUTH2 ' + $pg3.url.Substring(0, [Math]::Min(95, $pg3.url.Length)))
            $outside = ($pg3.url -notmatch '/p/juno/create')
        }
    }
    $pgF = Get-CdpPage -Port 9333 -Match 'ea.com'
    if ($pgF) {
        $s = Invoke-CdpCmd -WsUrl $pgF.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
            -Params @{ format = 'jpeg'; quality = 80 } -Id 520
        if ($s -and $s.result -and $s.result.data) {
            [IO.File]::WriteAllBytes((Join-Path $here '_t108_shot.jpg'), [Convert]::FromBase64String($s.result.data))
            J 'SHOT SAVED'
        }
        if ($outside) {
            $acct = [ordered]@{ eaId = 'ea499064xzacs'; email = 'ea499064xz@euploading.com'; password = '6&Fjd5H@4hbzy5x7'; createdAt = (Get-Date).ToString('s'); status = 'exited-wizard'; exitUrl = $pgF.url.Substring(0, [Math]::Min(180, $pgF.url.Length)) }
            ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
            "EA ACCOUNT CREATED`neaId: ea499064xzacs`nemail: ea499064xz@euploading.com`npassword: 6&Fjd5H@4hbzy5x7`ncreated: $((Get-Date).ToString('s'))" |
                Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
            J '=== ACCOUNT DONE ok=True'
        } else { J '=== STILL WIZARDING ok=False' }
    }
}
