# temp\_trig_run.ps1 — one command for a live trigger run (R6: no chat one-liners).
# Read-only memory + SendInput, so it is host-safe (R1).  Evidence goes to files:
#   temp\qk_trig1.txt         producer + trigger state (read THIS, not the chat)
#   temp\qk_trigger_state.txt trigger's own state feed, written on change (R3)
# Start qk_overlay.exe first (or the boxes have nowhere to land).
#
# No --no-elevate: gdrv3 needs an elevated token, so the producer relaunches itself via
# dumplive.run_elevated and writes the log through --out (an elevated child gets its own
# console, so the file is the only feed).  Append --fake=1 to run with no game up.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py   = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$out  = Join-Path $root 'temp\qk_trig1.txt'
$st   = Join-Path $root 'temp\qk_trigger_state.txt'
Remove-Item -LiteralPath $out, $st -ErrorAction SilentlyContinue

& $py (Join-Path $root 'ext\qk_esp.py') '--local=kern30120' '--secs=180' '--fov=90' `
      '--trigger=1' "--out=$out" @args
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $out
"--- trigger state file ---" | Add-Content -LiteralPath $out
Get-Content -LiteralPath $st -ErrorAction SilentlyContinue | Add-Content -LiteralPath $out
