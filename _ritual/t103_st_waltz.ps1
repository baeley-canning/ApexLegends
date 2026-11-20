# t103_st_waltz.ps1 - s8 email-NEXT -> auto-handle verify-code if appears -> ride -> land -> archive.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t103_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== WALTZ'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't88_lib.ps1')

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl
J ('AT ' + $pg.url.Substring(0, 90))

$ledgerPath = Join-Path $here '_ea_used_msgs.txt'
$used = @{}
if (Test-Path $ledgerPath) { Get-Content $ledgerPath | ForEach-Object { $used[$_.Trim()] = $true } }
function Save-Ledger { $used.Keys | Set-Content -Path $ledgerPath }

# STEP 1: email assert + next
$a = @'
(function(){
  var want='__MAIL__';
  var em=document.getElementById('email');
  if(em){ var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    if(em.value!==want){ st.call(em,want);
      ['keydown','keypress','input','keyup','change'].forEach(function(t){
        em.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});
      em.blur(); } }
  var nb=document.getElementById('basicInfoNextBtn')||
    (function(){var bs=document.querySelectorAll('button,[role=button],wf-button');
      for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
        if(/^next$/i.test(t))return bs[i];}return null;})();
  if(nb){nb.click();return 'NEXTED';} return 'NOBTN';
})()
'@
$a = $a.Replace('__MAIL__', $mail.address)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $a; returnByValue = $true } -Id 311
J ('STEP1 ' + $(if ($f1 -and $f1.result -and $f1.result.result) { [string]$f1.result.result.value } else { '?' }))

# STEP 2: adaptive phases 2..4
$victory = $false
foreach ($phase in 2..4) {
    $curStep = '?'
    for ($i = 1; $i -le 5; $i++) {
        Start-Sleep -Seconds 3
        $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
        $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
        $u = if ($p0) { $p0.url } else { '?' }
        if ($u -match 'execution=[^&]*s(\d+)') { $curStep = $Matches[1] }
        J ("ph$phase w$i s$curStep")
        if ($u -notmatch '/p/juno/create') { $victory = $true; break }
    }
    if ($victory) { break }
    $pg = Get-CdpPage -Port 9333 -Match 'ea.com'
    if (-not $pg) { break }
    $ws = $pg.webSocketDebuggerUrl
    $info = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({ttl:document.title,boxes:document.querySelectorAll('input[id^=emailVerifyCode]').length})";
        returnByValue = $true } -Id (320 + $phase)
    $vi = if ($info -and $info.result -and $info.result.result) { [string]$info.result.result.value } else { '{}' }
    J ("TYPE ph$phase " + $vi)
    if ($vi -match '"boxes":(\d+)' -and $Matches[1] -ne '0') {
        $c = $null
        for ($t = 1; $t -le 6; $t++) {
            $mc = Get-T88-Mail $hdr
            if ($mc -and -not $used.ContainsKey($mc.id)) { $c = $mc; break }
            Start-Sleep -Seconds 5
        }
        if ($c) {
            $used[$c.id] = $true; Save-Ledger
            $code = Get-T88-SubjCode $c.subject
            J ("OTP ph$phase code=$code msg=" + $c.id)
            if ($code) {
                $r = Invoke-T88-Submit $ws $code (330 + $phase)
                J ("SUB ph$phase " + $r)
                continue
            }
        }
        J 'NO OTP AVAILABLE'; break
    } else {
        $nx = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
            expression = "(function(){var bs=document.querySelectorAll('button,[role=button],wf-button');for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();if(/^next$|^continue$|^done$|^got it$/i.test(t)&&((bs[i].className||'').indexOf('disabled')<0)){bs[i].click();return 'CLICK '+t;}}return 'NOOPP';})()";
            returnByValue = $true } -Id (340 + $phase)
        J ("ADV ph$phase " + $(if ($nx -and $nx.result -and $nx.result.result) { [string]$nx.result.result.value } else { '?' }))
    }
}

# FINAL: land + archive
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $ld = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({ttl:document.title,heads:[].map.call(document.querySelectorAll('h1,h2'),function(e){return (e.innerText||'').replace(/\\s+/g,' ').trim().slice(0,50);}).filter(Boolean).slice(0,4)})";
        returnByValue = $true } -Id 350
    if ($ld -and $ld.result -and $ld.result.result) { J ('LAND ' + [string]$ld.result.result.value) }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 351
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t103_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
    $out = ($pg2.url -notmatch '/p/juno/create')
    if ($out) {
        $acct = [ordered]@{ eaId = 'ea499064xzacs'; email = $mail.address; password = '6&Fjd5H@4hbzy5x7'; createdAt = (Get-Date).ToString('s'); status = 'exited-wizard'; exitUrl = $pg2.url.Substring(0, [Math]::Min(180, $pg2.url.Length)) }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        "EA ACCOUNT CREATED`neaId: ea499064xzacs`nemail: $($mail.address)`npassword: 6&Fjd5H@4hbzy5x7`ncreated: $((Get-Date).ToString('s'))" |
            Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ACCOUNT DONE ok=True'
    } else { J '=== STILL INSIDE ok=False' }
}

