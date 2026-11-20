# t87_st_otp.ps1 - poll mail.tm for EA verification code, fill 6 OTP boxes, submit, harvest next page.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t87_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== OTP RETRIEVE'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }

# --- poll mailbox ---
$msgId = $null
for ($try = 1; $try -le 12; $try++) {
    try {
        $lst = Invoke-RestMethod -Uri 'https://api.mail.tm/messages?page=1' -Headers $hdr -Method Get -TimeoutSec 20
        $items = @($lst.'hydra:member')
        J ("poll $try count=" + $items.Count)
        if ($items.Count -gt 0) {
            # newest first per mail.tm ordering; still sort by createdAt desc
            $m = $items | Sort-Object { [datetime]$_.createdAt } -Descending | Select-Object -First 1
            $msgId = $m.id
            J ('MSG ' + $m.subject + ' FROM ' + ($m.from.address))
            break
        }
    } catch { J ("poll err $try " + $_.Exception.Message) }
    Start-Sleep -Seconds 5
}
if (-not $msgId) { J 'NO MAIL ARRIVED'; exit 1 }

# --- fetch full message & extract code ---
$full = Invoke-RestMethod -Uri ('https://api.mail.tm/messages/' + $msgId) -Headers $hdr -Method Get -TimeoutSec 20
$bodyTxt = ''
if ($full.text) { $bodyTxt = $full.text } else { $bodyTxt = ($full.html -join ' ') }
([string]$bodyTxt) | Out-File -Encoding utf8 (Join-Path $here '_ea_mail_body.txt')
$code = ''
if ($bodyTxt -match '\b(\d{6})\b') { $code = $Matches[1] }
if (-not $code) { J 'NO CODE FOUND IN BODY'; exit 1 }
J ('CODE ' + $code)
$code | Out-File -Encoding ascii (Join-Path $here '_ea_otp.txt')

# --- inject into page ---
. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE TARGET'; exit 1 }
J ('ON ' + $pg.url)

$js = @'
(function(){
  var code = '__CODE__';
  function fireSet(el,v){
    var st = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v);
    ['keydown','keypress','input','keyup','change'].forEach(function(t){
      el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));
    });
  }
  // fill each box
  for (var i=1;i<=6;i++){
    var e = document.getElementById('emailVerifyCode-'+i);
    if (!e) return 'MISSING BOX '+i;
    fireSet(e, code.charAt(i-1));
  }
  // defensive: consolidated hidden field
  var hid = document.getElementById('emailVerifyCode');
  if (hid) fireSet(hid, code);
  // click NEXT
  var nx=null; var bs=document.querySelectorAll('button, [role=button], wf-button');
  for (var b=0;b<bs.length;b++){ var t=(bs[b].textContent||'').replace(/\s+/g,' ').trim();
    if(/^next$/i.test(t)){ nx=bs[b]; break; } }
  var r='FILLED';
  if(nx){ r+=nx.disabled?' NEXTOFF':' NEXTGO'; if(!nx.disabled) nx.click(); }
  return r;
})()
'@
$js = $js.Replace('__CODE__', $code)
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $js; returnByValue = $true } -Id 51
$rv = '?'; if ($f -and $f.result -and $f.result.result) { $rv = [string]$f.result.result.value }
J ('INJECT ' + $rv)

# --- nav watch & harvest ---
Start-Sleep -Seconds 5
for ($i = 1; $i -le 6; $i++) {
    $locs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($locs | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    if ($p0) { J ("nav $i " + $p0.url) }
    Start-Sleep -Seconds 3
}
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $rd = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $f2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $rd; returnByValue = $true } -Id 52
    if ($f2 -and $f2.result -and $f2.result.result) {
        ([string]$f2.result.result.value) | Out-File -Encoding utf8 (Join-Path $here '_dom6_after_otp.txt')
        J 'DOM6 SAVED'
    }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 53
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t88_after_otp.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
J '=== DONE'
