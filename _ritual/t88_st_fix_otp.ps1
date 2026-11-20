# t88_st_fix_otp.ps1 - OTP attempt from mail SUBJECT; auto resend/repoll/retry; final harvest.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t88_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== OTP FIX'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't88_lib.ps1')

$m1 = Get-T88-Mail $hdr
if (-not $m1) { J 'NO MAIL EVER'; exit 1 }
J ('MSG "' + $m1.subject + '" @ ' + $m1.createdAt)
$code = Get-T88-SubjCode $m1.subject
if (-not $code) { J 'NO CODE IN SUBJECT'; exit 1 }
J ('ATT1 CODE ' + $code)
$code | Out-File -Encoding ascii (Join-Path $here '_ea_otp.txt')

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$r1 = Invoke-T88-Submit $pg.webSocketDebuggerUrl $code 61
J ('ATT1 ' + $r1)
$ok = Watch-T88-Nav 1 ${function:J}

if (-not $ok) {
    J ('STATE1 ' + (Get-T88-State $pg.webSocketDebuggerUrl 62))
    $rs = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "(function(){var ls=document.querySelectorAll('a,button,[role=button]');for(var i=0;i<ls.length;i++){var t=(ls[i].textContent||'').trim();if(/resend/i.test(t)){ls[i].click();return 'RESENT';}}return 'NORESEND';})()";
        returnByValue = $true } -Id 63
    J ('RESEND ' + $(if ($rs -and $rs.result -and $rs.result.result) { [string]$rs.result.result.value } else { '?' }))
    Start-Sleep -Seconds 12
    $m2 = Get-T88-Mail $hdr
    if ($m2) {
        J ('MSG2 "' + $m2.subject + '" id-diff=' + ($m2.id -ne $m1.id))
        $code2 = Get-T88-SubjCode $m2.subject
        if ($code2) {
            J ('ATT2 CODE ' + $code2)
            $code2 | Out-File -Encoding ascii (Join-Path $here '_ea_otp.txt')
            $pg = Get-CdpPage -Port 9333 -Match 'ea.com'
            if ($pg) {
                $r2 = Invoke-T88-Submit $pg.webSocketDebuggerUrl $code2 64
                J ('ATT2 ' + $r2)
                $ok = Watch-T88-Nav 2 ${function:J}
            }
        } else { J 'NO CODE IN MSG2' }
    } else { J 'NO MSG2' }
}

$pg3 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg3) {
    J ('FINAL URL ' + $pg3.url)
    J ('STATEF ' + (Get-T88-State $pg3.webSocketDebuggerUrl 65))
    $rd = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $fr = Invoke-CdpCmd -WsUrl $pg3.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $rd; returnByValue = $true } -Id 66
    if ($fr -and $fr.result -and $fr.result.result) {
        ([string]$fr.result.result.value) | Out-File -Encoding utf8 (Join-Path $here '_dom7_post_otp.txt')
        J 'DOM7 SAVED'
    }
    $s = Invoke-CdpCmd -WsUrl $pg3.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 67
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t89_final.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
J ('=== DONE ok=' + $ok)
