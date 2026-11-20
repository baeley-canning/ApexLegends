# t84_st_dob.ps1 - fill DOB selects on EA create page, advance to step 2, harvest it.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t84_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== DOB FILL'

. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE TARGET'; exit 1 }
J ('ON ' + $pg.url)

$fillJs = @'
(function(){
  function fire(e){ ['input','change'].forEach(function(t){
    e.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  var sels = document.querySelectorAll('select');
  var log = [];
  function pick(sel, want){
    var opts = sel.querySelectorAll('option');
    for (var i=0;i<opts.length;i++){
      if (opts[i].textContent.trim() === want || opts[i].value === want){
        sel.value = opts[i].value; fire(sel); return true;
      }
    }
    return false;
  }
  // identify selects by nearby label order: country, month, day, year
  var ids = [];
  sels.forEach(function(s,i){ ids.push(i+':'+(s.id||'?')+':opt'+s.options.length); });
  for (var k=0;k<sels.length;k++){
    var s = sels[k];
    var sid = (s.id||'').toLowerCase();
    var hasOptJune = false, hasOpt1995=false;
    s.querySelectorAll('option').forEach ? null : null;
    var os = s.querySelectorAll('option');
    for (var z=0;z<os.length;z++){ if(os[z].textContent.trim()==='June') hasOptJune=true; if(os[z].textContent.trim()==='1995') hasOpt1995=true; }
    if (sid.indexOf('country')>=0){ /* keep default */ log.push('country kept'); }
    else if (hasOptJune){ pick(s,'June'); log.push('month->June'); }
    else if (hasOpt1995){ pick(s,'1995'); log.push('year->1995'); }
    else if (!isNaN(parseInt(os.length>1?os[1].textContent:null)) ){ if(pick(s,'15')) log.push('day->15'); }
  }
  // verify
  var done=[]; sels.forEach(function(s){ if(s.value) done.push(s.value); });
  // click NEXT when enabled
  var nx=null;
  var bs=document.querySelectorAll('button, [role=button], wf-button');
  for (var b=0;b<bs.length;b++){ var t=(bs[b].textContent||'').replace(/\s+/g,' ').trim(); if(/^next$/i.test(t)){ nx=bs[b]; break; } }
  var nxTxt='NOBUTTON';
  if(nx){ nxTxt='disabled='+nx.disabled+' cls='+(nx.className||'').toString().slice(0,40);
          if(!nx.disabled){ nx.click(); nxTxt+=' CLICKED'; } }
  return 'SEL['+ids.join(';')+'] SET['+log.join(',')+'] VAL['+done.join('|')+'] NX('+nxTxt+')';
})()
'@
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $fillJs; returnByValue = $true } -Id 21
$val = '?'
if ($f -and $f.result -and $f.result.result) { $val = [string]$f.result.result.value }
J ('FILL RESULT ' + $val)

# nav watch
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 2
    $locs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($locs | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    if ($p0) { J ("nav $i " + $p0.url) }
}

# harvest page 2
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $js = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $f2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $js; returnByValue = $true } -Id 22
    if ($f2 -and $f2.result -and $f2.result.result) {
        ([string]$f2.result.result.value) | Out-File -Encoding utf8 (Join-Path $here '_dom3_step2.txt')
        J 'DOM3 SAVED'
    }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 82 } -Id 23
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t84_step2.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'STEP2 SHOT SAVED'
    }
}
J '=== DONE'
