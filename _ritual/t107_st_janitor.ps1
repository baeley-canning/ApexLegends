# t107_st_janitor.ps1 - universal step-driver: census -> species action -> loop to freedom.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t107_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== JANITOR'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't88_lib.ps1')

$ledgerPath = Join-Path $here '_ea_used_msgs.txt'
$used = @{}
if (Test-Path $ledgerPath) { Get-Content $ledgerPath | ForEach-Object { $used[$_.Trim()] = $true } }

$win = $false
foreach ($cycle in 1..5) {
    $step = '?'
    for ($i = 1; $i -le 4; $i++) {
        Start-Sleep -Seconds 3
        $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
        $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
        $u = if ($p0) { $p0.url } else { '?' }
        if ($u -match 'execution=[^&]*s(\d+)') { $step = $Matches[1] }
        J ("c$cycle w$i s$step")
        if ($u -notmatch '/p/juno/create') { $win = $true; break }
    }
    if ($win) { break }

    $pg = Get-CdpPage -Port 9333 -Match 'ea.com'
    if (-not $pg) { J 'PAGE LOST'; break }
    $ws = $pg.webSocketDebuggerUrl

    $sp = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({ttl:document.title,oid:!!document.getElementById('originId'),em:!!document.getElementById('email'),boxes:document.querySelectorAll('input[id^=emailVerifyCode-]').length})";
        returnByValue = $true } -Id (450 + $cycle)
    $vs = ''; if ($sp -and $sp.result -and $sp.result.result) { $vs = [string]$sp.result.result.value }
    J ("SPECIES c$cycle " + $vs)

    # ANCHOR_SPECIES_HANDLERS
    if ($vs -match '"boxes":(\d+)' -and $Matches[1] -ne '0') {
        $c = $null
        for ($t = 1; $t -le 6; $t++) {
            $mc = Get-T88-Mail $hdr
            if ($mc -and -not $used.ContainsKey($mc.id)) { $c = $mc; break }
            Start-Sleep -Seconds 5
        }
        if ($c) {
            $used[$c.id] = $true; $used.Keys | Set-Content -Path $ledgerPath
            $code = Get-T88-SubjCode $c.subject
            J ("OTP c$cycle code=$code")
            if ($code) {
                $rr = Invoke-T88-Submit $ws $code (480 + $cycle)
                J ("VSUB c$cycle " + $rr)
                Start-Sleep -Seconds 4
            }
        } else { J "NO OTP c$cycle"; break }
    }
    elseif ($vs -match '"oid":true') {
        $ea = @'
(function(){
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
  typeInto(idEl,'__EAID__'); if(pwEl)typeInto(pwEl,'__PASS__');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  var fm=document.querySelectorAll('form')[1]||idEl.closest('form');
  try{fm.requestSubmit();return 'FORGED';}catch(e){return 'ERR';}
})()
'@
        $ea = $ea.Replace('__EAID__', 'ea499064xzacs').Replace('__PASS__', '6&Fjd5H@4hbzy5x7')
        $r = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $ea; returnByValue = $true } -Id (460 + $cycle)
        J ("EAID c$cycle " + $(if ($r -and $r.result) { [string]$r.result.result.value } else { '?' }))
        Start-Sleep -Seconds 4
        $u2 = "location.assign('" + ($pg.url -replace "'", '').Substring(0, 4000) + "')"
        Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $u2; returnByValue = $true } -Id (470 + $cycle) | Out-Null
        Start-Sleep -Seconds 5
    }
    elseif ($vs -match '"em":true') {
        $em = @'
(function(){
  var want='__MAIL__';
  var el=document.getElementById('email');
  if(el){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    if(el.value!==want){st.call(el,want);
      ['keydown','keypress','input','keyup','change'].forEach(function(t){
        el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});
      el.blur();}}
  var nb=document.getElementById('basicInfoNextBtn');
  if(nb){nb.click();return 'NEXTED';}return 'NOBTN';
})()
'@
        $em = $em.Replace('__MAIL__', $mail.address)
        $r2 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $em; returnByValue = $true } -Id (490 + $cycle)
        J ("EMAIL c$cycle " + $(if ($r2 -and $r2.result) { [string]$r2.result.result.value } else { '?' }))
        Start-Sleep -Seconds 4
    }
    else { J ("UNKNOWN c$cycle"); break }
}

# ANCHOR_LANDING
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $ld = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({ttl:document.title,heads:[].map.call(document.querySelectorAll('h1,h2'),function(e){return (e.innerText||'').replace(/\\s+/g,' ').trim().slice(0,55);}).filter(Boolean).slice(0,5)})";
        returnByValue = $true } -Id 500
    if ($ld -and $ld.result -and $ld.result.result) { J ('LAND ' + [string]$ld.result.result.value) }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 501
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t107_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
    if ($win) {
        $acct = [ordered]@{ eaId = 'ea499064xzacs'; email = $mail.address; password = '6&Fjd5H@4hbzy5x7'; createdAt = (Get-Date).ToString('s'); status = 'exited-wizard'; exitUrl = $pg2.url.Substring(0, [Math]::Min(180, $pg2.url.Length)) }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        "EA ACCOUNT CREATED`neaId: ea499064xzacs`nemail: $($mail.address)`npassword: 6&Fjd5H@4hbzy5x7`ncreated: $((Get-Date).ToString('s'))" |
            Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ACCOUNT DONE ok=True'
    } else { J '=== CYCLES SPENT ok=False' }
}

