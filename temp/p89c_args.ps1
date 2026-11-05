$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Location -LiteralPath $repo
$o = 'C:\Users\New User\AppData\Local\Temp\_p89_args.txt'
Remove-Item -LiteralPath $o -ErrorAction SilentlyContinue
$ev = Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = 1001; StartTime = (Get-Date).Date} -ErrorAction SilentlyContinue
foreach ($e in $ev) {
  $m = [regex]::Match($e.Message, 'bugcheck was: (0x[0-9a-f]+) \(0x([0-9a-f]+), 0x([0-9a-f]+), 0x([0-9a-f]+), 0x([0-9a-f]+)\)')
  if (-not $m.Success) { continue }
  $code = $m.Groups[1].Value
  $a1 = $m.Groups[2].Value
  $a2 = $m.Groups[3].Value
  $a3 = $m.Groups[4].Value
  $off = ''
  if ($a2 -match '^0x[0-9a-f]*?([0-9a-f]{4})$') { $off = $matches[1] }
  $mod = ''
  if ($a2 -match '^(0x[0-9a-f]{4,})([0-9a-f]{4})$') { $hi = [Convert]::ToUInt64($matches[1], 16) -band 0xFFFF0000; $mod = ('0x{0:x}' -f $hi) }
  "{0} code={1} a1={2} a2={3} a3={4} low16={5} seg64k={6}" -f $e.TimeCreated.ToString('HH:mm:ss'), $code, $a1, $a2, $a3, $off, $mod | Out-File -LiteralPath $o -Append -Encoding utf8
}
"count=$($ev.Count)" | Out-File -LiteralPath $o -Append -Encoding utf8
