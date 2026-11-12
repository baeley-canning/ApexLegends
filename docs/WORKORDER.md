# WORKORDER - Apex external ESP, docs-only field reconciliation

Written 2026-11-09. Executor: next agent (Opus seat). Mode: docs only, no game,
no driver, no transport code. Nothing here may touch kernel/driver state (R1).

MISSION: turn an offset corpus into a class-labelled, evidence-numbered field map so
that later transport work (_mk17.py) is worth a game launch. Finish W1-W3 and STOP.

## 0. Why this is urgent and cheap

temp\dm32.txt is a static datamap reconstruction of the shipping r5apex_dx12.exe -
179 classes, 3226 fields, 2326 named, one '### DT_<Class>' block per class,每 field
carrying off= sz= t= fl= and a line number. No game required. The corpus (REF_TABLE
and friends) is a name list with 26174491-era offsets; dm32 IS this build.

THE RULE THAT MAKES OR BREAKS EVERYTHING: the same name recurs at different offsets
in different classes (m_localOrigin 0x18/0x20, m_armorType 0x48D8/0x16D4, m_ammoInClip
0x15D0/0x1600). An offset without a class label is not a result.

## 1. Read in this order before typing

  AGENTS.md  (R1-R10; R5 numbered outputs, R9 no PASS when half was skipped)
  docs/ref/PLAN_MASTER.md      (fork note + stage ladder + BLOCK clause)
  docs/ref/PROTOCOL_VERIFY.md  (P1-P10, how an offset becomes a fact)
  docs/ref/ANTIPATTERNS.md     (A1-A19, read before writing anything)
  docs/ref/DELTA_MATRIX.md     (already-measured deltas; do not recompute)
  docs/ref/REF_TABLE.md        (names only, all values UNVERIFIED)
  docs/ref/TICKETS_*.md, BACKLOG.md (context for what the offsets are FOR)
  FACTS.md, PLAN.md            (only truth table / only next-step authority)

## 2. W1 - mechanical extraction (the deliverable that unblocks everything)

Write docs/ref/NETVAR_LOCAL.md from temp\dm32.txt, mechanically, per class:

  for every '### DT_<Class>' heading: one section; under it,每 'field N 0xA' row
  as: '  off=0xNNN sz=0xN t=0xN fl=0xN 'name' L####'  - name in single quotes when
  the row is named, '(unnamed)' when not. Keep class, offset, size, line number.

ACCEPT: 179 class sections; 3226 field rows total; the heading count and the row
total must equal dm32's OWN summary (temp\dm32.txt L4577-4578: named 2326,
total 3226). Spot-check 10 rows (including m_iHealth on DT_Player 0x330 sz4 and
m_ammoInClip on DT_WeaponX_LocalWeaponData 0x1600) and quote their dm32 line
numbers. Helper that already exists: temp\_fields_dm32.txt (2061 named rows,
'name off sz class Lnnn') - usable, but NETVAR_LOCAL.md must be built from the
SOURCE file, not only from the helper.

## 3. W2 - reconcile REF_TABLE names to W1 offsets

Write docs/ref/FIELD_MAP_LOCAL.md: ONE row per REF_TABLE name, columns
'name | class(es) | local off(s) | pack value | delta | status | evidence L####'.
status MUST be one of: MATCH / DELTA / CLASS-DEPENDENT / ABSENT / N/A.
N/A is for module-relative names (dm32 cannot answer). ABSENT is a result too -
write the row, do not drop it. UNRESOLVED (off=0x00000 rows, m_vecAbsOrigin) is
its own status line under the row, never a fired delta.

ACCEPT: every entity-relative REF_TABLE name appears exactly once; no pack value
was edited in REF_TABLE.md; no averaging of pack and local.

## 4. W3 - verdict

Write docs/TASK_STATE.md, three lines:
  line 1: W1/W2/W3 each PASS/PARTIAL/FAIL
  line 2: the checksum you actually counted (headings, rows, names)
  line 3: the exact next action, one sentence.
If any half was skipped, the verdict is PARTIAL, never PASS (R9).

## 5. Hard constraints

- Do NOT edit REF_TABLE.md, do NOT rewrite FACTS.md or PLAN.md wholesale.
- Do NOT correct offsets by uniform delta (six whole clusters in DELTA_MATRIX
  sit at delta 0x0 while four DT_Player state fields are -0x8; one correction
  is wrong in both directions - A2/A16).
- Do NOT promote a lone field. Clusters only (A9/P5).
- Every number you cite must be reproducible from temp\dm32.txt by line number.
- Write files with [IO.File]::WriteAllText(path, string) using 'n (backtick-n) line
  breaks - here-strings in the VS Code shell bit the last session. Read the byte
  count back after every write.
- Keep the tree: no new top-level folders; everything lands under docs\ or docs\ref\

## 6. Explicitly NOT in this workorder (do not start them)

- _mk17.py or any transport: BLOCKED, no pid exists (Q1 probe unrun).
- Any host/VM/kernel step, any game launch, any reboot.
- dm11/dm13/dm16 re-parsing beyond what W1 cites.
- Fixing the fork conflation inside PLAN_MASTER - it is already annotated.

## 7. If documents disagree

FACTS.md wins on facts, PLAN.md wins on next steps. dm32 wins over both for
offsets. If you find dm32 contradicts a FACTS entry, correct FACTS.md by ONE line.
