$ErrorActionPreference = 'Continue'
$lg = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_fix1.txt'
$dir = 'C:\p9\xcerts'
function Put($s) { Add-Content -LiteralPath $lg -Value ([string]$s) -Encoding utf8 }
function Cap($a) { return ((@($a) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join ' ~~ ') }
Remove-Item -LiteralPath $lg -ErrorAction SilentlyContinue
Put ('fix1 ' + (Get-Date -Format s))
Put ('elev=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Put ('user=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

Put '=== A. bcd BEFORE ==='
Put ('enum: ' + (Cap (& bcdedit.exe 2>&1)))
Put ('enum-current: ' + (Cap (& bcdedit.exe /enum '{current}' 2>&1)))

Put '=== B. flip TESTSIGNING ==='
$r = Cap (& bcdedit.exe /set testsigning on 2>&1)
Put ('set testsigning on rc=' + $LASTEXITCODE + ' :: ' + $r)
$r2 = Cap (& bcdedit.exe /set '{current}' testsigning on 2>&1)
Put ('set {current} testsigning on rc=' + $LASTEXITCODE + ' :: ' + $r2)

Put '=== C. bcd AFTER ==='
Put ('enum: ' + (Cap (& bcdedit.exe 2>&1)))
Put ('startopts: ' + (Cap (& reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control' /v SystemStartOptions 2>&1)))

Put '=== D. service image paths ==='
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) {
    Put ('  ' + $s + ' :: ' + (Cap (& reg.exe query ('HKLM\SYSTEM\CurrentControlSet\Services\' + $s) /v ImagePath 2>&1)))
}

Put '=== E. extract signers from the 577 images ==='
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$certs = New-Object System.Collections.Generic.List[object]
foreach ($f in @('C:\Windows\System32\drivers\apexdrv.sys', 'C:\p26cat\apexdrv_build.sys', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys')) {
    if (-not (Test-Path -LiteralPath $f)) { Put ('  missing ' + $f); continue }
    try {
        $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromSignedFile($f)
        Put ('  signer ' + $f + ' :: ' + $c.Subject + ' thumb=' + $c.Thumbprint)
        $certs.Add($c)
        $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $ch.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $ch.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
        $ok = $ch.Build($c)
        Put ('    chainok=' + $ok + ' depth=' + $ch.ChainElements.Count + ' status=' + (Cap (@($ch.ChainStatus | ForEach-Object { $_.Status }))))
        foreach ($el in $ch.ChainElements) { Put ('      el ' + $el.Certificate.Subject); $certs.Add($el.Certificate) }
    } catch { Put ('  cfs-err ' + $f + ' :: ' + $_.Exception.Message) }
}

Put '=== F. apex-ish certs in My stores + loose .cer files ==='
foreach ($p in @('Cert:\LocalMachine\My', 'Cert:\CurrentUser\My')) {
    foreach ($c in @(Get-ChildItem -Path $p -ErrorAction SilentlyContinue)) {
        if ($c.Subject -match 'Apex|QwenKern') { $certs.Add($c); Put ('  my ' + $p + ' :: ' + $c.Subject + ' thumb=' + $c.Thumbprint) }
    }
}
foreach ($f in @(Get-ChildItem -Path @('C:\p9', 'C:\p26cat', 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual') -Recurse -Depth 2 -Include *.cer, *.crt -ErrorAction SilentlyContinue)) {
    if ($f.DirectoryName -eq $dir) { continue }
    try {
        $cc = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($f.FullName)
        if ($cc.Subject -match 'Apex|QwenKern') { $certs.Add($cc); Put ('  cer ' + $f.FullName + ' :: ' + $cc.Subject) }
    } catch { }
}

Put '=== G. install every apex cert into Root + TrustedPublisher + CA ==='
$done = @{}
foreach ($c in $certs) {
    if ($done.ContainsKey($c.Thumbprint)) { continue }
    $done[$c.Thumbprint] = 1
    foreach ($sn in @('Root', 'TrustedPublisher', 'CA')) {
        $has = $false
        foreach ($x in @(Get-ChildItem -Path ('Cert:\LocalMachine\' + $sn) -ErrorAction SilentlyContinue)) { if ($x.Thumbprint -eq $c.Thumbprint) { $has = $true; break } }
        if ($has) { continue }
        $p = Join-Path $dir ($sn + '_' + $c.Thumbprint + '.cer')
        [System.IO.File]::WriteAllBytes($p, $c.RawData)
        Put ('  ADD ' + $sn + ' ' + $c.Subject + ' :: ' + (Cap (& certutil.exe -addstore -f $sn $p 2>&1)))
    }
}
Put ('  total-distinct-certs=' + $done.Count)

Put '=== H. sc start (pre-reboot baseline) ==='
foreach ($s in @('apexdrv', 'apexdrv_cat', 'kernprobe')) {
    $out = Cap (& sc.exe start $s 2>&1)
    Put ('  start ' + $s + ' rc=' + $LASTEXITCODE + ' :: ' + $out)
    Start-Sleep -Milliseconds 600
    Put ('    q: ' + (Cap (& sc.exe query $s 2>&1)))
}

Put '=== I. post-reboot logon task ==='
Put ('  create: ' + (Cap (& schtasks.exe /create /tn p9post /tr 'C:\p9\_post1.cmd' /sc onlogon /rl HIGHEST /it /f 2>&1)))
Put ('  query: ' + (Cap (& schtasks.exe /query /tn p9post /fo list 2>&1)))
Put ('done ' + (Get-Date -Format s))
