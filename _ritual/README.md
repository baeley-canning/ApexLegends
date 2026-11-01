# `_ritual/` — probe harness and raw evidence

This folder is why any claim in this repo is believable. Every probe is `pNN_<topic>.ps1` plus a
wrapper `runNN.cmd`; the probe writes its own output file `pNN_<topic>.txt` next to itself. Scripts
self-elevate (one UAC prompt) and are safe to re-run. `_index.txt` is the running log of findings —
read the tail of it first, it is the narrative.

## Conventions

- `pNN` = probe number, monotonic. New probe = new number, never overwrite an old result file.
- A probe logs: state before, what it did, timestamps, raw evidence, RESULT line, VERDICT block.
- Never delete a probe that produced a claim quoted in `QwenKernPremium/docs/`.
- Wrappers exist so a probe can be re-fired post-reboot from `RunOnce` / a shortcut.
- PowerShell 5.1 trap that has bitten this folder: `Func()` on a zero-arg function parses as command
  syntax in expression context (`if(F())`, `$x = F()`). Use `Func`, `(Func)` or `$x = Func`.

## The gate chain (read in this order)

| File | What it establishes |
|---|---|
| `p13_*` | Javelin/EAAC install strings and layout (`C:\Program Files\EA\AC`) |
| `p20*`, `p24*`-`p26*` | driver signing: 577 at load, catalog/cross-sign attempts, why they failed |
| `p27_gate.ps1`, `run27.cmd`, `p27_gate*.txt` | the gate itself: popup id 26 with apexdrv loaded |
| `p29_gate2.ps1`, `p29_gate2*` | A/B: flag vs our driver. Stopping the driver swaps refusal family, does not fix it |
| `p30*` | de-register + rename every apexdrv*.sys so a launch is a vanilla baseline |
| `p31b`, `p31_bootverify.txt` | post-reboot: popup gone, game 300 s clean — testsigning is a kill-flag |
| `p33_flagflip.ps1`, `run33.cmd`, `p33_flagflip.txt` | flag-flip T1/T2/T3: the popup follows the flag source |
| `p34_matrix.ps1`, `run34.cmd` | driver-stopped vs driver-loaded with the flag off, 1 s poll + exit code |

## Interpreting the results safely

- p33's `died` flag is a trap: it only ticks if a 5 s poll *saw* the game up, so a ~6 s exit reads as
  `died=False` and its GREEN branch fires while `alive=False`. Trust `alive`, and use p34 for timing.
- Only the `$RX` regex (`Security Violation|must be disabled to start|signing integrity checks must be
  enabled|...`) is grep-able in the event log. The EAAC in-game panel
  ("This software cannot be used at the same time as the game") is drawn inside the game window and
  leaves NO event — capture all events, and watch the screen.
- A verdict must name the variable it changed and hold everything else constant; p34 varies only
  driver presence.

## Helper state files

- `_p33_sso.bak` — original `SystemStartOptions` string before the T3 scrub (restore with
  `Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control -Name SystemStartOptions -Value (Get-Content _p33_sso.bak)`).
- `bcd_before_*.bcd` (+ `.LOG*`) — full BCD exports taken before each boot-flag change.
- `apexdrv_lab_*.cer` — the lab CA / leaf / oneshot certs used by the p24-p26 signing attempts.
- `runNN.log` — wrapper start/end stamps, useful to correlate a run with the terminal timeline.
