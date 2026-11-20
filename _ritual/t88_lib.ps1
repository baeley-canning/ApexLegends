# t88_lib.ps1 - shared helpers for OTP fix (sourced by t88_st_fix_otp.ps1)
function Get-T88-Mail($hdr) {
    $lst = Invoke-RestMethod -Uri 'https://api.mail.tm/messages?page=1' -Headers $hdr -Method Get -TimeoutSec 20
    $items = @($lst.'hydra:member')
    if ($items.Count -eq 0) { return $null }
    return ($items | Sort-Object { [datetime]$_.createdAt } -Descending | Select-Object -First 1)
}
function Get-T88-SubjCode($subj) {
    if ($subj -match '-\s*(\d{6})\s*$') { return $Matches[1] }
    $clean = $subj -replace '[#\w]*\d{6}[\w]*', ' '
    foreach ($mt in [regex]::Matches($clean, '\b(\d{6})\b')) { return $mt.Groups[1].Value }
    return $null
}
function Invoke-T88-Submit([string]$Ws, [string]$code, [int]$callId) {
    $js = @'
(function(){
  var code = '__CODE__';
  function fs(el,v){ var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v); ['keydown','keypress','input','keyup','change'].forEach(function(t){
      el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  for (var i=1;i<=6;i++){ var e=document.getElementById('emailVerifyCode-'+i); if(!e) return 'MISSBOX'; fs(e,code.charAt(i-1)); }
  var hid=document.getElementById('emailVerifyCode'); if(hid) fs(hid,code);
  var nx=null; var bs=document.querySelectorAll('button, [role=button], wf-button');
  for (var b=0;b<bs.length;b++){ var t=(bs[b].textContent||'').replace(/\s+/g,' ').trim(); if(/^next$/i.test(t)){ nx=bs[b]; break; } }
  if(nx&&!nx.disabled){ nx.click(); return 'SUBMITTED'; }
  return 'NEXTDISABLED';
})()
'@
    $js = $js.Replace('__CODE__', $code)
    $fr = Invoke-CdpCmd -WsUrl $Ws -Method 'Runtime.evaluate' -Params @{ expression = $js; returnByValue = $true } -Id $callId
    if ($fr -and $fr.result -and $fr.result.result) { return [string]$fr.result.result.value }
    return 'EVALFAIL'
}
function Get-T88-State([string]$Ws, [int]$callId) {
    $expr = "(function(){var u=location.href.match(/execution=[^&]*s(\d+)/);var eb=document.querySelector('.otkinput-error,.error,[class*=error]');var al=document.querySelector('[class*=snack],[class*=alert],[role=alert]');return JSON.stringify({step:u?u[1]:'?',err:eb?eb.innerText:'',alert:al?al.innerText:''});})()"
    $st = Invoke-CdpCmd -WsUrl $Ws -Method 'Runtime.evaluate' -Params @{ expression = $expr; returnByValue = $true } -Id $callId
    if ($st -and $st.result -and $st.result.result) { return $st.result.result.value }
    return '{}'
}
function Watch-T88-Nav([int]$round, [scriptblock]$LogFn) {
    for ($i = 1; $i -le 5; $i++) {
        Start-Sleep -Seconds 3
        $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
        $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
        $u = if ($p0) { $p0.url } else { '?' }
        & $LogFn ("watch$round $i " + $u)
        if ($u -match 's4|welcome|finish|dobform|profile|ea\.com/(?!signin)') { return $true }
    }
    return $false
}
