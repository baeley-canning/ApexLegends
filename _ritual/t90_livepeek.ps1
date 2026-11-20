# t90_livepeek.ps1 - on-demand live census+screenshot of the active non-wizard tab.
param()
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t) { Write-Host 'NO NON-WIZARD TAB'; exit 1 }
Write-Host ('URL: ' + $t.url.Substring(0, [Math]::Min(95, $t.url.Length)))

$q = @'
(function(){
  function txt(sel,n,len){return [].map.call(document.querySelectorAll(sel),function(e){
    if(n&&!(e.offsetWidth||e.offsetHeight))return null;
    var t=(e.innerText||e.value||'').replace(/\s+/g,' ').trim();
    return t?t.slice(0,len||50):null;}).filter(Boolean).slice(0,n||10);}
  return JSON.stringify({
    ttl:document.title.slice(0,35),
    heads:txt('h1,h2,h3',6,55),
    labels:txt('label,p',8,50),
    inputs:[].map.call(document.querySelectorAll('input:not([type=hidden])'),function(e){
      return (e.id||e.name||'?')+'/'+e.type+'='+(e.type==='checkbox'?e.checked:(e.value||'').slice(0,18));}).slice(0,8),
    btns:txt('button,a[class*=otkbtn],[role=button]',8,20),
    errs:txt('[class*=error]',3,60)
  });
})()
'@
$r = Invoke-CdpCmd -WsUrl $t.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{ expression = $q; returnByValue = $true } -Id 910
Write-Host ('DATA: ' + $r.result.result.value)

$s = Invoke-CdpCmd -WsUrl $t.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 911
if ($s -and $s.result -and $s.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_live_now.jpg'), [Convert]::FromBase64String($s.result.data))
    Write-Host 'SNAP-OK'
} else { Write-Host 'SNAP-FAIL' }
