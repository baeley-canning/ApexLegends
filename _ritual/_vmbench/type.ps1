# type.ps1 - send a string to the guest as scancodes
param([string]$Text, [string]$Path, [string]$Vm = 'Win11-Test2')
if ($Path) { $Text = ((Get-Content -LiteralPath $Path -Raw) -replace "`r?`n$", '') }
$vm = $Vm
$vm = 'Win11-Test2'
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'

$low = @{
    'a'='1e';'b'='30';'c'='2e';'d'='20';'e'='12';'f'='21';'g'='22';'h'='23';'i'='17';'j'='24';'k'='25';'l'='26';'m'='32';
    'n'='31';'o'='18';'p'='19';'q'='10';'r'='13';'s'='1f';'t'='14';'u'='16';'v'='2f';'w'='11';'x'='2d';'y'='15';'z'='2c';
    '0'='0b';'1'='02';'2'='03';'3'='04';'4'='05';'5'='06';'6'='07';'7'='08';'8'='09';'9'='0a';
    ' '='39';'-'='0c';'='='0d';'['='1a';']'='1b';'\'='2b';';'='27';"'"='28';'`'='29';','='33';'.'='34';'/'='35'
}
$shift = @{ ':'='27';'"'='28';'_'='0c';'+'='0d';'('='09';')'='0a';'*'='08';'&'='07';'%'='06';'$'='05';'#'='04';'@'="'";'!'='02';'^'='07';'{'='1a';'}'='1b';'|'='2b';'<'='33';'>'='34';'?'='35';'~'='29' }

$codes = New-Object System.Collections.Generic.List[string]
foreach ($ch in $Text.ToCharArray()) {
    $s = [string]$ch
    if ($low.ContainsKey($s)) { $mk = $low[$s]; $codes.Add($mk); $codes.Add(('{0:x2}' -f ([Convert]::ToInt32($mk,16) -bor 0x80))) }
    elseif ($shift.ContainsKey($s)) { $mk = $shift[$s]; $codes.Add('2a'); $codes.Add($mk); $codes.Add(('{0:x2}' -f ([Convert]::ToInt32($mk,16) -bor 0x80))); $codes.Add('aa') }
    elseif ($s -eq ' ') { $codes.Add('39'); $codes.Add('b9') }
}
for ($i = 0; $i -lt $codes.Count; $i += 60) {
    $chunk = $codes.GetRange($i, [Math]::Min(60, $codes.Count - $i))
    & $vb controlvm $vm keyboardputscancode @chunk | Out-Null
    Start-Sleep -Milliseconds 90
}
