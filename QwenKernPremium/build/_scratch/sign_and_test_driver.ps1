# ============================================================================
# build\sign_and_test_driver.ps1  — ELEVATED: make apexdrv.sys loadable on THIS
# box, load it, and run the two measurements it unlocks:
#     * --kernel-probe  (Q10: can kernel context do what user mode cannot?)
#     * --method=kernel (B3: the rung that has been SKIPping since PHASE 1)
#
# Signing: a self-signed code-signing certificate placed in LocalMachine\My and
# trusted by LocalMachine\Root + LocalMachine\TrustedPublisher.  That is what the
# kernel loader requires for a non-WHQL driver when Secure Boot is on (SHA-256,
# EKU 1.3.6.1.5.5.7.3.3).  No bcdedit / testsigning, no reboot.
#
# Run:  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile',
#         '-ExecutionPolicy','Bypass','-File','...\build\sign_and_test_driver.ps1'
# ============================================================================
$ErrorActionPreference = 'Continue'

$root   = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev     = Join-Path $root 'build\phase1_evidence'
$driver = Join-Path $root 'build\apexdrv.sys'
$log    = Join-Path $ev 'driver_sign_load.txt'
$signtool = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'

function Write-Log([string] $text) { $text | Out-File -Encoding utf8 -Append $log }

"== driver sign + load $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
"driver : $driver ($((Get-Item $driver -ErrorAction SilentlyContinue).Length) bytes)" | Out-File -Encoding utf8 -Append $log
"signtool: $signtool" | Out-File -Encoding utf8 -Append $log

# A launcher started ELEVATED (by a previous run) locks build\apex_launcher.exe
# and makes the next Rebuild fail with "access to the path is denied".
taskkill /F /IM apex_launcher.exe *>&1 | Out-File -Encoding utf8 -Append $log
Start-Sleep -Milliseconds 300

# --- 0: rebuild + gate ------------------------------------------------------
# The driver test has to exercise the binaries that are in the tree right now
# (and the kill above is what makes a Rebuild possible at all).
Set-Location $root
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\BuildGate.ps1') *>&1 |
    Out-File -Encoding utf8 (Join-Path $ev 'gate_for_driver.txt')
$gateExit = $LASTEXITCODE
Write-Log "gate   : EXIT=$gateExit"
if ($gateExit -ne 0) {
    Write-Log 'gate failed - aborting before touching the driver'
    'ABORTED(gate)' | Out-File -Encoding utf8 (Join-Path $ev 'driver_done.txt')
    exit 1
}

# --- 1: certificate ---------------------------------------------------------
$subject = 'CN=ApexDrv Dev (QwenKern Premium)'
$cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -eq $subject -and $_.HasPrivateKey } |
        Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject `
        -CertStoreLocation 'Cert:\LocalMachine\My' -KeyUsage DigitalSignature `
        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(3)
    Write-Log "cert   : created $($cert.Thumbprint)"
} else {
    Write-Log "cert   : reusing $($cert.Thumbprint)"
}
$cerPath = Join-Path $root 'build\apexdrv_dev.cer'
Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
foreach ($store in 'Root', 'TrustedPublisher') {
    Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\LocalMachine\$store" | Out-Null
    Write-Log "cert   : imported into LocalMachine\$store"
}

# --- 2: sign + verify ------------------------------------------------------
# /sm = machine store (the certificate was created there); without it signtool
# searches CurrentUser\My and reports "no certificates met the criteria".
& $signtool sign /sm /s My /fd sha256 /sha1 $cert.Thumbprint /v $driver *>&1 |
    Out-File -Encoding utf8 -Append $log
Write-Log "signtool EXIT=$LASTEXITCODE"
$signature = Get-AuthenticodeSignature $driver
Write-Log "signature: $($signature.Status)  signer: $($signature.SignerCertificate.Subject)"

# --- 2b: stage outside OneDrive -------------------------------------------
# A driver image belongs outside the sync root anyway; C:\ProgramData is a
# plain local path with no reparse point in it.
$stageDir = 'C:\ProgramData\QwenKern'
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
$stagedDriver = Join-Path $stageDir 'apexdrv.sys'
Copy-Item $driver $stagedDriver -Force
Write-Log "staged : $stagedDriver ($((Get-Item $stagedDriver).Length) bytes)"

# --- 3: register + load -----------------------------------------------------
# StartService returned 123 (ERROR_INVALID_NAME) twice, and the path was never
# the reason: 'sc create ... "binPath= X"' stores the ImagePath as ' X' - WITH
# a leading space - for kernel drivers, and NtLoadDriver then fails to parse
# it (STATUS_OBJECT_NAME_INVALID).  Writing the value into the registry
# directly gives the exact string, and the tool prints it back for the log.
$serviceKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv'
$imagePath  = '\??\' + $stagedDriver
if (-not (Get-Service apexdrv -ErrorAction SilentlyContinue)) {
    (sc.exe create apexdrv type= kernel start= demand) 2>&1 | Out-File -Encoding utf8 -Append $log
}
Set-ItemProperty -Path $serviceKey -Name ImagePath -Value $imagePath -Type ExpandString
Write-Log "imagePath : '$((Get-ItemProperty $serviceKey).ImagePath)' (leading space would be fatal)"
(sc.exe qc apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
$service = Get-Service apexdrv -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne 'Running') {
    try { Start-Service apexdrv } catch { Write-Log "Start-Service: $_" }
}
Start-Sleep -Milliseconds 500
(sc.exe query apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
$running = (Get-Service apexdrv -ErrorAction SilentlyContinue).Status -eq 'Running'
Write-Log "loaded : $running"

# --- 4: measurements -------------------------------------------------------
Set-Location (Join-Path $root 'build')
$apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
Write-Log "apex   : PID $apex"
if ($apex) {
    .\apex_launcher.exe --kernel-probe --driver=$stagedDriver --pid=$apex *>&1 |
        Out-File -Encoding utf8 (Join-Path $ev 'kernel_probe.txt')
    "KERNEL_PROBE_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'kernel_probe.txt')

    .\apex_launcher.exe --method=kernel --driver=$stagedDriver --no-wait --pid=$apex *>&1 |
        Out-File -Encoding utf8 (Join-Path $ev 'b3_ladder.txt')
    "B3_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'b3_ladder.txt')
}

# --- 5: leave as little behind as possible --------------------------------
if ($running) {
    try { Stop-Service apexdrv -Force } catch { Write-Log "Stop-Service: $_" }
}
(sc.exe delete apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
Write-Log "service deleted (a reboot may be needed before the image unloads fully)"

'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'driver_done.txt')
