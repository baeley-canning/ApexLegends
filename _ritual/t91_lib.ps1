# t91_lib.ps1 - identity generator + strict error reader for the finish step
function New-EaSecrets {
    $chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'.ToCharArray()
    $r = New-Object System.Random
    # EA ID: base + 3 random tail -> 13 chars, <=16
    $tail = -join (1..3 | ForEach-Object { $chars[$r.Next($chars.Length)] })
    $eaId = 'ea499064xz' + $tail
    # password: guaranteed upper+lower+digit+symbol, 16 len, no repeats
    $up = 'ABCDEFGHJKMNPQRTUVWXYZ'; $lo = 'abcdefghjkmnpqrstuvwxyziop'; $dg = '23456789'; $sy = '!@#$%^&*?'
    $pool = ($up + $lo + $dg + $sy).ToCharArray()
    $pw = [char[]]@(
        $up[$r.Next($up.Length)], $lo[$r.Next($lo.Length)],
        $dg[$r.Next($dg.Length)], $sy[$r.Next($sy.Length)]
    ) + (1..12 | ForEach-Object { $pool[$r.Next($pool.Length)] })
    # shuffle deterministically-random
    0..($pw.Length-1) | ForEach-Object { $i=$r.Next($pw.Length); $t=$pw[$_]; $pw[$_]=$pw[$i]; $pw[$i]=$t }
    ,@($eaId, (-join $pw))
}
function Read-LiveErrors([string]$Ws, [int]$callId) {
    $expr = @'
(function(){
  var out={fields:{},page:[]};
  document.querySelectorAll('[class*=error],[role=alert]').forEach(function(e){
    if(!e.offsetParent && getComputedStyle(e).position!=='fixed') return;
    var t=(e.innerText||'').replace(/\s+/g,' ').trim(); if(!t) return;
    var inp=e.closest('.otkinput, .otkform-element-wrapper');
    if(inp){ var f=inp.querySelector('input'); var key=f?(f.id||f.name):'?';
      if(out.fields[key]) out.fields[key]+=' | '+t; else out.fields[key]=t; }
    else out.page.push(t);
  });
  var u=location.href.match(/execution=[^&]*s(\d+)/);
  out.step=u?u[1]:'?';
  return JSON.stringify(out);
})()
'@
    $st = Invoke-CdpCmd -WsUrl $Ws -Method 'Runtime.evaluate' -Params @{ expression = $expr; returnByValue = $true } -Id $callId
    if ($st -and $st.result -and $st.result.result) { return [string]$st.result.result.value }
    return '{"err":"readerfail"}'
}
