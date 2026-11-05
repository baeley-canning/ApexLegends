# p53_an.ps1 -- read-only shape analysis of p53_dump_*.txt. No device access.
# Per hit page: marker count, zero density, printable run, and 24 bytes of ASCII
# either side of every marked byte. Also greps every dump for the FDB magic.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$L = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $repo 'temp') -Filter 'p53_dump_*.txt' | Sort-Object Name)) {
  [void]$L.Add('##### ' + $f.Name)
  $rows = Get-Content -LiteralPath $f.FullName
  foreach ($r in $rows) { if ($r -match 'FDB') { [void]$L.Add('  FDB: ' + $r) } }
  $page = $null; $mk = 0; $zero = 0; $print = 0; $ctx = New-Object System.Collections.ArrayList; $lines = New-Object System.Collections.ArrayList
  foreach ($r in ($rows + @('PAGE  end'))) {
    if ($r -match '^PAGE\s+(\S+|end)') {
      if ($page -and $mk -gt 0) {
        [void]$L.Add(('  page={0} hits={1} zerobytes={2}/4096 printable={3}/4096' -f $page, $mk, $zero, $print))
        foreach ($c in $ctx) { [void]$L.Add('    ' + $c) }
      }
      $page = $Matches[1]; $mk = 0; $zero = 0; $print = 0; $ctx.Clear()
      continue
    }
    if ($r -notmatch '^    ([0-9a-f]{6})  (\S.*?) \|') { continue }
    $off = $Matches[1]; $cell = $Matches[2]
    # 3-char cells: "xx " or "xx<" marks the hit on that byte
    $b = 0
    for ($i = 0; $i -lt $cell.Length; $i += 3) {
      $pair = $cell.Substring($i, 2); $hit = $false
      if ($cell.Length -gt $i + 2 -and $cell[$i + 2] -eq '<') { $hit = $true }
      $v = 0; if ([int]::TryParse($pair, 'HexNumber', $null, [ref]$v)) {
        if ($v -eq 0) { $zero++ }
        if ($v -ge 0x20 -and $v -le 0x7e) { $print++ }
        if ($hit) { $mk++; [void]$ctx.Add(('hit @0x{0}+0x{1:x2} row={2}' -f $page, ([Convert]::ToInt32($off, 16) + $b), $cell)) }
      }
      $b++
    }
  }
}
$L | Set-Content -LiteralPath (Join-Path $repo 'temp\p53_an.txt') -Encoding utf8
'an_lines=' + $L.Count
