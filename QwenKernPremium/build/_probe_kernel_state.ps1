# build\_probe_kernel_state.ps1
#
# Read-only facts about the B3 (kernel) rung: boot config, Secure Boot, the
# driver's signature and whether apexdrv is currently loaded.  Elevation only
# because bcdedit/sc want it.
$out = 'C:\ProgramData\_qwen_kernel_state.txt'
$lines = @()

$lines += '--- bcdedit {current} ---'
$lines += (& bcdedit /enum '{current}' 2>&1 | Out-String)

$lines += '--- secure boot ---'
try { $lines += "SecureBootEnabled=$((Confirm-SecureBootUEFI))" }
catch { $lines += "SecureBoot=<error: $($_.Exception.Message)>" }

$drv = Join-Path 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build' 'apexdrv.sys'
$lines += '--- driver file ---'
if (Test-Path $drv) {
    $sig = Get-AuthenticodeSignature -FilePath $drv
    $lines += ("path={0}`nsize={1}`nsignature={2}`nsigner={3}" -f $drv, (Get-Item $drv).Length, $sig.Status, $sig.SignerCertificate.Subject)
} else { $lines += 'apexdrv.sys NOT FOUND' }

$lines += '--- sc start (readiness only, not started) ---'
$lines += (& sc.exe query apexdrv 2>&1 | Out-String)
$lines += (& sc.exe qc apexdrv 2>&1 | Out-String)

$lines | Out-File -FilePath $out -Encoding utf8
