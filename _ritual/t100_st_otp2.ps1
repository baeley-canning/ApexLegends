# t100_st_otp2.ps1 - second verification round: newest-message OTP from subject, dedupe, submit, fallback resend.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t100_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== OTP2'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
$hdr = @{ Authorization = 'Bearer ' + $mail.token }
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't88_lib.ps1')

# consume ledger
$ledgerPath = Join-Path $here '_ea_used_msgs.txt'
$used = @{}
if (Test-Path $ledgerPath) {
    Get-Content $ledgerPath | ForEach-Object { $used[$_.Trim()] = $true }
}

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
J ('AT ' + $pg.url.Substring(0, 90))
$ws = $pg.webSocketDebuggerUrl

# fetch freshest unconsumed message
$mNew = $null
for ($t = 1; $t -le 8; $t++) {
    $cand = Get-T88-Mail $hdr
    if ($cand -and -not $used.ContainsKey($cand.id)) { $mNew = $cand; break }
    J ("waiting $t newest=" + $(if ($cand) { $cand.id } else { 'none' }))
    Start-Sleep -Seconds 5
}
if (-not $mNew) { J 'NO FRESH MESSAGE'; exit 1 }
$used[$mNew.id] = $true
$used.Keys | Set-Content -Path $ledgerPath
$code = Get-T88-SubjCode $mNew.subject
if (-not $code) { J ('SUBJ UNCLEAR: ' + $mNew.subject); exit 1 }
J ('CODE2 ' + $code + ' (msg ' + $mNew.id + ')')

# fill six boxes blunt (proven on s3), click NEXT
$ok = $false
for ($attempt = 1; $attempt -le 2; $attempt++) {
    $r = Invoke-T88-Submit $ws $code (261 + $attempt)
    J ("att$attempt $r")
    $moved = $false
    for ($i = 1; $i -le 4; $i++) {
        Start-Sleep -Seconds 3
        $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
        $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
        $u = if ($p0) { $p0.url } else { '?' }
        J ("w$i " + $u.Substring(0, [Math]::Min(80, $u.Length)))
        if ($u -match '/s\d+&' -and ($u -notmatch '/s6&')) { $moved = $true; break }
        if ($u -notmatch '/p/juno/create') { $moved = $true; break }
    }
    if ($moved) { $ok = $true; break }
    if ($attempt -eq 1) {
        # resend then await new message
        $rs = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
            expression = "(function(){var ls=document.querySelectorAll('a,button,[role=button]');for(var i=0;i<ls.length;i++){var tx=(ls[i].textContent||'').trim();if(/resend/i.test(tx)){ls[i].click();return 'RESENT';}}return 'NORESEND';})()";
            returnByValue = $true } -Id 270
        J ('RESEND ' + $(if ($rs -and $rs.result -and $rs.result.result) { [string]$rs.result.result.value } else { '?' }))
        Start-Sleep -Seconds 10
        $m2 = Get-T88-Mail $hdr
        if ($m2 -and -not $used.ContainsKey($m2.id)) {
            $used[$m2.id] = $true; $used.Keys | Set-Content -Path $ledgerPath
            $nc = Get-T88-SubjCode $m2.subject
            if ($nc) { $code = $nc; J ('CODE2B ' + $nc) }
        }
    }
}

# land / archive
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 275
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t100_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
    J ('ENDURL ' + $pg2.url.Substring(0, [Math]::Min(100, $pg2.url.Length)))
    if ($ok) {
        $acct = [ordered]@{
            eaId      = 'ea499064xzacs'
            email     = $mail.address
            password  = '6&Fjd5H@4hbzy5x7'
            createdAt = (Get-Date).ToString('s')
            status    = 'wizard-exited-or-near'
            exitUrl   = $pg2.url.Substring(0, [Math]::Min(180, $pg2.url.Length))
        }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        "EA ACCOUNT (phase2 verified)`neaId: ea499064xzacs`nemail: $($mail.address)`npassword: 6&Fjd5H@4hbzy5x7`nupdated: $((Get-Date).ToString('s'))" |
            Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ARCHIVED ok=True'
    } else { J '=== STILL VERIFYING ok=False' }
}
