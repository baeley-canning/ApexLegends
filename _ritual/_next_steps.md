# NEXT STEPS — k11 boot-value soak (03/11 21:19)

The fix is one line of logic: restore the DSE value `kdu` printed *before* the flip, never the
constant 6. That is now patched in `h1_dse_host.ps1`. Nothing else about the recipe changed.
Unproven until a guest survives the KPP horizon *without* being reverted — reverting early is what
made `k9` look like a pass (R1 broken in substance, not letter).

## Where the bench is right now (21:13)

- `VM-D`: reverted to `pre-k10`, booted headless again. `k10` aborted on a real bug (`DrvState`
  called before its definition → `UNCAUGHT`, DSE left at 0, driver RUNNING), so the run was
  discarded and re-issued as **k11** with the definition hoisted and a `finally` restore added.
- Run order now: `k10_soak.ps1` = aborted evidence, `k11_soak.ps1` = the live probe. `guest-k10.log`
  is kept (R5), `guest-k11.log` is the new state feed.
- `cur.ps1` = k11 (sha 641E42DFD9BF4752), `active.txt`=k11, server listening 8080, snapshot `pre-k10` intact.

## The correction the first boot handed us

The guest prints `value: 6` — its boot value **is** 6, the very constant h1 hardcoded. So the soak
cannot distinguish "restore 6" from "restore the recorded value" by outcome; the host boot value is
16 and that is where the defect actually bites. What the guest soak does prove: the parse, the
readback, and that a driver can sit resident 45 min with the flags byte back at boot content.
Treat a guest `SOAK CLEAN` as "mechanism works, 45 min coexistence in this build", never as "the
host is fixed". That is the k9 mistake with a longer timer.

## Step 1 — soak, do not revert (BLOCKING)

`k11` runs baseline 577 → prv ladder → captures `PRE-DSE` → `sc start apexdrv` (expect 0/RUNNING)
→ restore `-dse <PRE-DSE>` → independent readback → 45 × 60 s heartbeats, driver left RUNNING.
Watch `C:\p37vm\guest-k11.log` (or `_ritual\_plan_watch11.ps1`, which appends `RESULT:` verdicts):

| observation | verdict |
|---|---|
| `RESTORE verified=True readback=6 expect=6` | fix behaves as designed (6 *is* this guest's boot value) |
| heartbeats continue past HB 27 (worst-case horizon) | survives scan #1 |
| `RESULT: SOAK CLEAN 45 min` | **fix proven, Step 2 unblocked** |
| POSTs stop mid-soak + later `SOAK BREAK: guest rebooted` | still broken → read `--- minidumps ---` |
| `PRE-DSE UNPARSED` | parse is fragile on this kdu build, stop and fix the regex |

Expected guest DSE pre-value may differ from the host's 16 — that is fine and is the point.
Do not touch the VM, do not snapshot-revert, do not run anything else in the guest while it soaks.

## Step 2 — host, one boot, h1 then h2 back to back (after Step 1 passes)

`h1` alone is not evidence; the gate (`h2`, 1800 s) cannot outlive a ~20 min horizon, so both must
share the boot. Order: `_ritual\_plan_hostpost.ps1` is only for **after**; the pre-state is already
recorded (`_ritual\_plan_hostpre.txt`, boot 20:37, `apexdrv` STOPPED, 0 dumps, VBS 0).

1. `_ritual\h1_dse_host.ps1` — expect baseline **577** (not 0: DSE is armed at boot on the host),
   `PRE-DSE=16`, write + verify, `sc start` rc 0 / `STATE: 4 RUNNING`, `RESTORE verified=True
   readback=16`. Anything whose readback is not 16 means the fallback bit and the run is void.
2. Within a minute, `_ritual\h2_gate.ps1` (`run_h2.cmd`, 1800 s). GREEN needs the game alive
   30 min with zero refusal events.
3. `_ritual\_plan_hostpost.ps1` in the same boot — it re-reads boot time, dumps, 1001s and says
   `SAME BOOT` / `REBOOTED - uptime diff invalid`.
4. Verdict is "process still alive at t+30 min AND no 0x109", never h1's own PASS line (R3).

User consents to the possible reboot first (R2) — a failed fix costs the session. If the host
bugchecks, the drop is already on disk; do not re-run in the same boot.

## Step 3 — record the decision, then the wording

- Decide host-mode primary (PatchGuard tolerated, h1+h2 same boot) vs VM path promoted and host
  demoted to fallback. Write the choice into `STATE.md` next to the correction at line 257.
- Then strike "6 = armed" at `STATE.md` ~line 60 and point it at the recorded-pre-value rule.
- `apexdrv` rest-of-day status stays "resident only with a DSE write" — unchanged by a pass.

## Step 4 — non-blocking, can happen during the soak

EA app sign-in is user-mode only: no reboot, no driver, safe on the current boot. Do it now rather
than after Step 2, so the gate run has a signed-in account warm (the 07:20 boot failed on that).

## Guardrails

- R5: `k11` is a new number, own `guest-k11.log`; `guest-k10.log` is kept as the aborted-evidence file.
- R3: verdict is the readback line and the continued POSTs, never kdu's exit code (1 = success too).
- R4: `VM-D` carries `pre-k11`… actually `pre-k10` for a clean re-run; host h1 restores in its `finally`.
- R1: host gets fingers only after Step 1 is clean. R2: no reboot without asking.

## Artifacts

`C:\p37vm\payload\k11_soak.ps1` (probe), `_ritual\_plan_start11.ps1` (bench bring-up),
`_ritual\_plan_boot11.ps1` (boot recovery), `_ritual\_plan_watch11.ps1` (read-only watcher),
`C:\p37vm\guest-k11.log` (state feed), `_ritual\_crash_finding.txt` (why the value matters),
`_ritual\_plan_hostpre.txt` / `_plan_hostpost.ps1` (R3 halves), `_ritual\_plan_sig11.txt` (proven
append-only heartbeats).

