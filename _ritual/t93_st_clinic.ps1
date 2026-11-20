# t93_st_clinic.ps1 - rebuilt identity gen (flat return), gated submit with readback validation.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t93_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== CLINIC'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

# ---- identity generator: returns FLAT string[], consumed by index ----
function New-FlatSecrets {
    $alnum = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'.ToCharArray()
    $r = New-Object System.Random
    $tail = -join (1..3 | ForEach-Object { $alnum[$r.Next($alnum.Length)] })
    $eaId = 'ea499064xz' + $tail
    $up = 'ABCDEFGHJKMNPQRTUVWXYZ'; $lo = 'abcdefghjkmnpqrstuvwxyzaq'
    $dg = '23456789'; $sy = '!@#$%^&*?'
    $pool = ($up + $lo + $dg + $sy).ToCharArray()
    $core = @(
        $up[$r.Next($up.Length)], $lo[$r.Next($lo.Length)],
        $dg[$r.Next($dg.Length)], $sy[$r.Next($sy.Length)]
    )
    1..12 | ForEach-Object { $core += $pool[$r.Next($pool.Length)] }
    0..($core.Length - 1) | ForEach-Object { $s = $r.Next($core.Length); $t = $core[$_]; $core[$_] = $core[$s]; $core[$s] = $t }
    return @($eaId, (-join $core))   # flat two-string array
}

$s = New-FlatSecrets
$id = [string]$s[0]
$pw = [string]$s[1]
J ("TYPES idType=$($id.GetType().Name) pwType=$($pw.GetType().Name)")
J ("VALIDATE id='$id' len=$($id.Length) pwLen=$($pw.Length)")
if ($id -notmatch '^[A-Za-z0-9]{4,16}$') { J 'ABORT id-shape'; exit 1 }
if ($pw.Length -lt 12)                 { J 'ABORT pw-len';   exit 1 }

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }

# single eval: clear -> fill -> readback -> defuse -> READY verdict
$js = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  function fs(el,v){ var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v); ['keydown','keypress','input','keyup','change'].forEach(function(t){
      el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  var vis=[].slice.call(document.querySelectorAll('input')).filter(function(x){
    return (x.offsetWidth||x.offsetHeight)&&(!x.type||(x.type!=='hidden'&&x.type!=='checkbox'));});
  var idEl=document.getElementById('originId')||vis[0];
  vis.forEach(function(x){ fs(x,''); });
  fs(idEl, eaId);
  var vis2=[].slice.call(document.querySelectorAll('input')).filter(function(x){
    return (x.offsetWidth||x.offsetHeight)&&x.type==='password';});
  var pwEl=vis2.filter(function(x){return x!==idEl;})[0]||(vis2[0]||null)||((vis2.length?vis2[0]:(vis[vis.indexOf(idEl)+1]||null)));
  if(!pwEl) return JSON.stringify({verdict:'NOPW'});
  fs(pwEl, pass);
  var a1=idEl.value, a2=pwEl.value, fx=[];
  if(a1!==eaId){ fx.push('id'); fs(idEl,''); fs(idEl,eaId); }
  if(a2!==pass){ fx.push('pw'); fs(pwEl,''); fs(pwEl,pass); }
  var ready = (idEl.value===eaId && pwEl.value===pass);
  var chk=document.getElementById('readAccept')||document.querySelector('input[type=checkbox]');
  if(chk&&!chk.checked) chk.click();
  return JSON.stringify({verdict: ready?'READY':'DIRTY',
    idNow:idEl.value, pwLenNow:pwEl.value.length, fixes:fx,
    chk: chk?(chk.checked?'on':'off'):'absent'});
})()
'@
$js = $js.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $js; returnByValue = $true } -Id 111
$rv = '?'; if ($f -and $f.result -and $f.result.result) { $rv = [string]$f.result.result.value }
J ('STATE ' + $rv)

if ($rv -match '"verdict":"READY"' -and $rv -match '"chk":"on"') {
    $ck = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "(function(){var bs=document.querySelectorAll('button,[role=button],wf-button');for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){if(bs[i].disabled)return 'DISABLED';bs[i].click();return 'CLICKED';}}return 'NOBTN';})()";
        returnByValue = $true } -Id 112
    J ('CLICK ' + $(if ($ck -and $ck.result) { [string]$ck.result.result.value } else { '?' }))
    $left = $false
    for ($i = 1; $i -le 8; $i++) {
        Start-Sleep -Seconds 3
        $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
        $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
        $u = if ($p0) { $p0.url } else { '?' }
        J ("nav $i " + $u.Substring(0, [Math]::Min(70, $u.Length)))
        if ($u -notmatch '/p/juno/create') { $left = $true; break }
    }
} else { J 'NO CLICK - not ready'; $left = $false }

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $s2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 113
    if ($s2 -and $s2.result -and $s2.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t93_shot.jpg'), [Convert]::FromBase64String($s2.result.data))
        J 'SHOT SAVED'
    }
}
if ($left -and $pg2) {
    $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); finalUrl = $pg2.url }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J '=== ARCHIVED ok=True'
} else { J '=== NOT YET ok=False' }
