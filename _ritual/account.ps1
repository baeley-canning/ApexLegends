# account.ps1 - READ-ONLY account stamp. No driver, no service, no elevation.
# Writes _ritual/_account.txt: every EAID on this box, its ban flag, and which one the
# EA app is currently signed in as.  In-game evidence names this file (FACTS rule 4).
# Why: the 18/11 ban made every older evidence file ambiguous about WHICH account it
# measured.  Same failure class as h328's "PASS is notepad", different axis.
$ErrorActionPreference = 'SilentlyContinue'
$d = 'C:\Users\New User\AppData\Local\Electronic Arts\EA Desktop'
$sg = Join-Path $env:USERPROFILE 'Saved Games\Respawn\Apex\assets\temp'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_account.txt'
$L = New-Object System.Collections.ArrayList
function W($s) { [void]$L.Add("$s") }

W "account stamp  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  host=$env:COMPUTERNAME"
$users = @(Get-ChildItem -LiteralPath $d -Filter 'user_*.ini' -File | Sort-Object LastWriteTime -Descending)
if (-not $users.Count) { W 'no EA app user files - app never signed in on this box' }

$active = $null
foreach ($f in $users) {
  $kv = @{}
  foreach ($line in (Get-Content -LiteralPath $f.FullName -TotalCount 40)) {
    if ($line -match '^\s*user\.userid\s*=\s*(\d+)') { $kv.uid = $Matches[1] }
    if ($line -match '^\s*user\.gamebanmodaldisplayed\s*=\s*(\d)') { $kv.ban = $Matches[1] }
  }
  if (-not $active) { $active = $f }
  $tag = if ($f -eq $active) { 'ACTIVE ' } else { '       ' }
  $ban = if ($kv.ban -eq '1') { 'BANNED-MODAL' } elseif ($kv.ban) { 'modal x' + $kv.ban } else { 'no ban flag' }
  $game = if (Test-Path -LiteralPath (Join-Path $sg ("str_r5_CL_02_" + $kv.uid))) { 'apex-profile' } else { '-' }
  W ("  {0}EAID {1,-16} last {2}  {3}  {4}" -f $tag, $kv.uid, $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $ban, $game)
}

if ($active) {
  $auid = (Select-String -LiteralPath $active.FullName -Pattern '^user\.userid=(\d+)' | Select-Object -First 1).Matches[0].Groups[1].Value
  W ''
  W "ACTIVE_EAID: $auid"
  W "ACTIVE_BANNED: $(if ((Select-String -LiteralPath $active.FullName -Pattern '^user\.gamebanmodaldisplayed=1') ) { 'yes' } else { 'no' })"
  W "ACCOUNT_COUNT: $($users.Count)"
  W 'stamp this file in every in-game evidence header; rerun after any account switch'
  [void]$L.Add("VERDICT: stamp written for EAID $auid")
} else {
  [void]$L.Add('VERDICT: no account on box')
}
$L -join "`r`n" | Out-File -LiteralPath $out -Encoding utf8
Write-Host "wrote $out"
