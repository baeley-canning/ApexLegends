# t99_st_exit.ps1 - advance past s5 (add email), track wizard exit, archive account.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t99_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== EXIT'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl
J ('FROM ' + $pg.url.Substring(0, 90))

# ensure email intact (server prefilled; force-assert ours) then click next
$act = @'
(function(){
  var want='__MAIL__';
  var em=document.getElementById('email');
  if(em){
    var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    if(em.value!==want){ st.call(em,want);
      ['keydown','keypress','input','keyup','change'].forEach(function(t){
        em.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); });
      em.blur(); }
  }
  var nb=document.getElementById('basicInfoNextBtn');
  if(nb){var lk=(nb.className||'').indexOf('disabled')>=0;
    nb.click(); return JSON.stringify({clicked:true,wasLocked:lk,emailNow:em?em.value:'?'});}
  return JSON.stringify({clicked:false,noBtn:true});
})()
'@
$act = $act.Replace('__MAIL__', $mail.address)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $act; returnByValue = $true } -Id 251
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('ACT ' + $v1)

# follow the ride until leaves /juno/create entirely
$exitUrl = ''
for ($i = 1; $i -le 7; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    J ("ride $i " + $u.Substring(0, [Math]::Min(85, $u.Length)))
    $exitUrl = $u
    if ($u -notmatch '/p/juno/create') { break }
}

# land: heads + confirmation signals
$land = @'
(function(){
  var hs=[];
  [].forEach.call(document.querySelectorAll('h1,h2,h3,.otktitle,[class*=welcome]'),
    function(el){var t=(el.innerText||'').replace(/\s+/g,' ').trim();if(t)hs.push(t.slice(0,70));});
  var av=document.querySelector('[class*=avatar],[class*=profile],[data-testid*=account]');
  return JSON.stringify({heads:hs.slice(0,8),avatar:!!av,who:(av?av.innerText||'':'').slice(0,40)});
})()
'@
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $f2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = $land; returnByValue = $true } -Id 252
    if ($f2 -and $f2.result -and $f2.result.result) { J ('LAND ' + [string]$f2.result.result.value) }

    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 253
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t99_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }

    if ($exitUrl -and $exitUrl -notmatch '/p/juno/create') {
        $acct = [ordered]@{
            eaId        = 'ea499064xzacs'
            email       = $mail.address
            password    = '6&Fjd5H@4hbzy5x7'
            createdAt   = (Get-Date).ToString('s')
            exitUrl     = $exitUrl.Substring(0, [Math]::Min(180, $exitUrl.Length))
            mailAccount = $mail.accountId
        }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        $done = "EA ACCOUNT CREATED`neaId: ea499064xzacs`nemail: $($mail.address)`npassword: 6&Fjd5H@4hbzy5x7`ncreated: $((Get-Date).ToString('s'))`nexit: $($exitUrl.Substring(0,[Math]::Min(120,$exitUrl.Length)))"
        $done | Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ACCOUNT DONE ok=True'
    } else { J '=== WIZARD HOLDS ok=False' }
}
