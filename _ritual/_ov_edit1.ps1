$ErrorActionPreference = "Stop"
$rit  = "C:\Users\New User\OneDrive\Desktop\cheating\_ritual"
$qkp  = "C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium"

# ---- d3d12_overlay.cpp: replace EmitMenu, insert public API -------------------
$f    = Join-Path $qkp "src\d3d12_overlay.cpp"
$text = [IO.File]::ReadAllText($f)
[IO.File]::WriteAllText($f + ".bak", $text, [Text.UTF8Encoding]::new($false))

$newMenu = [IO.File]::ReadAllText((Join-Path $rit "_ov_pa.txt"))
$api     = [IO.File]::ReadAllText((Join-Path $rit "_ov_pb.txt"))

$pat = "(?s)// Draws the menu: header.*?\r\n\}\r\n"
$m = [regex]::Matches($text, $pat)
if ($m.Count -ne 1) { throw "EmitMenu anchor count = $($m.Count) (expected 1)" }
$text = [regex]::Replace($text, $pat, { $newMenu })

$anchor = "} // namespace D3D12Overlay"
$cnt = ([regex]::Matches($text, [regex]::Escape($anchor))).Count
if ($cnt -ne 1) { throw "namespace-close anchor count = $cnt (expected 1)" }
$text = $text.Replace($anchor, $api + "`r`n" + $anchor)
[IO.File]::WriteAllText($f, $text, [Text.UTF8Encoding]::new($false))
"d3d12_overlay.cpp: EmitMenu replaced + API inserted (len $($text.Length))"

# ---- hooks.cpp: replace WndProcHook ----------------------------------------
$f2    = Join-Path $qkp "src\hooks.cpp"
$text2 = [IO.File]::ReadAllText($f2)
[IO.File]::WriteAllText($f2 + ".bak", $text2, [Text.UTF8Encoding]::new($true))

$newWp = [IO.File]::ReadAllText((Join-Path $rit "_ov_pc.txt"))
$pat2 = "(?s)LRESULT CALLBACK GameHooks::WndProcHook.*?\r\n\}\r\n"
$m2 = [regex]::Matches($text2, $pat2)
if ($m2.Count -ne 1) { throw "WndProcHook anchor count = $($m2.Count) (expected 1)" }
$text2 = [regex]::Replace($text2, $pat2, { $newWp })
[IO.File]::WriteAllText($f2, $text2, [Text.UTF8Encoding]::new($true))
"hooks.cpp: WndProcHook replaced (len $($text2.Length))"