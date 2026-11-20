# t91_st_finish2.ps1 - regenerate identity, refill, submit, verify with strict reader, archive.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t91_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== FINISH2'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't91_lib.ps1')

$id, $pw = New-EaSecrets
J ("IDENTITY eaId=$id pwLen=" + $pw.Length)

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
J ('PRE ' + (Read-LiveErrors $pg.webSocketDebuggerUrl 91))

$js = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  function fs(el,v){ var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v); ['keydown','keypress','input','keyup','change'].forEach(function(t){
      el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  fs(document.getElementById('originId'), eaId);
  var pwEl=document.querySelector('input[type=password]'); if(!pwEl) return 'NOPWFIELD';
  fs(pwEl, pass);
  var chk=document.getElementById('readAccept')||document.querySelector('input[type=checkbox]');
  var cstat='none';
  if(chk){ if(!chk.checked){ chk.click(); } cstat=chk.checked?'on':'still-off'; }
  var nx=null; var bs=document.querySelectorAll('button, [role=button], wf-button');
  for (var b=0;b<bs.length;b++){ var t=(bs[b].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){ nx=bs[b]; break; } }
  if(nx&&!nx.disabled){ nx.click(); return 'OK chk='+cstat; }
  return 'NXOFF chk='+cstat;
})()
'@
$js = $js.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $js; returnByValue = $true } -Id 92
$rv = '?'; if ($f -and $f.result -and $f.result.result) { $rv = [string]$f.result.result.value }
J ('SUBMIT ' + $rv)

# wait for exit from juno/create OR read live errors
$left = $false
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    J ("nav $i " + $u.Substring(0, [Math]::Min(80, $u.Length)))
    if ($u -notmatch '/p/juno/create') { $left = $true; break }
}
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
$post = Read-LiveErrors $pg2.webSocketDebuggerUrl 93
J ('POST ' + $post)

if ($pg2) {
    $rd = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $fr = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $rd; returnByValue = $true } -Id 94
    if ($fr -and $fr.result -and $fr.result.result) {
        ([string]$fr.result.result.value) | Out-File -Encoding utf8 (Join-Path $here '_dom9_finish2.txt')
        J 'DOM9 SAVED'
    }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 95
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t91_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}

if ($left) {
    $acct = [ordered]@{
        eaId      = $id
        email     = $mail.address
        password  = $pw
        createdAt = (Get-Date).ToString('s')
        finalUrl  = $pg2.url
    }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J '=== ACCOUNT ARCHIVED ok=True'
} else {
    J '=== STILL BLOCKED ok=False'
}
