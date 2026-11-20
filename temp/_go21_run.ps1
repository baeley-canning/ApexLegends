# temp\_go21_run.ps1 -- go21: point the proven direct lane at the live game (R6: scripted).
# Overlay must already be running (started earlier, pid noted in transcript).
# Producer chain: qk_esp.py scans ALL usable physical RAM for the mate-name needles,
# boxes every position-deduped hit whose (name-0xEEC) floats are plausible world coords.
# Evidence files (R3):
#   temp\qk_go21_esp.txt   producer + box counts (READ THIS, not the chat)
# Zero-trigger config: boxes only; triggerbot is a later leg.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py   = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$out  = Join-Path $root 'temp\qk_go21_esp.txt'
Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue

& $py (Join-Path $root 'ext\qk_esp.py') '--local=kern30120' `
      '--mates=Nessie,nessie,NESSIE' '--secs=300' '--fov=90' `
      "--out=$out" @args
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $out
