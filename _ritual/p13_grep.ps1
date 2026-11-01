$ErrorActionPreference = 'Continue'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = Join-Path $r 'p13_grep.txt'
if (Test-Path $o) { Remove-Item $o -Force }
function W($s) { $s | Add-Content -LiteralPath $o }

W ('=== p13 grep ' + (Get-Date) + ' ===')

$files = @('p13_strall_launcherdll.txt', 'p13_strall_gameservicedll.txt')

$pats = @(
  'Security Violation', 'securityviolation', 'Violation', 'violation',
  'Unsupported', 'unsupported', 'ATTESTATION', 'Attestation', 'attest',
  'TESTSIGNING', 'test signing', 'Test Sign', 'testsign',
  'Bypass', 'bypass', 'fltmc', 'sc start',
  'DriverStore', 'unsigned', 'revoked', 'not signed',
  'Virtualization', 'Virtualisation', 'hypervisor', 'Hypervisor',
  'Secure Boot', 'SecureBoot', 'UEFI', 'legacy', 'MBR',
  'SkuPolicy', 'EmodePolicy', 'VerifiedAndReputable', 'WDAC', 'SiPolicy',
  'unacceptable', 'integrity', 'Tamper', 'tamper',
  '0xFFFF', '4294924', 'EA Javelin', 'Javelin', 'Skyfall', 'skyfall',
  'eaanticheat', 'EAAntiCheat'
)

foreach ($fn in $files) {
  $p = Join-Path $r $fn
  W ''
  if (-not (Test-Path $p)) { W ("##### $fn ABSENT"); continue }
  W ('##### ' + $fn + ' : ' + (Get-Item $p).Length + ' bytes')
  foreach ($pt in $pats) {
    $m = Select-String -LiteralPath $p -Pattern $pt -AllMatches -CaseSensitive:$false
    if ($m) {
      W ("--- [$pt] hits=" + @($m).Count)
      $m | Select-Object -First 20 | ForEach-Object { W ('    ' + $_.Line) }
    }
  }
}
W ''
W ('=== DONE grep ' + (Get-Date) + ' ===')
