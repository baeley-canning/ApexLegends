# Stage 0, next — replace this only with a read-backed PASS

Success here means a consistent process-identity/DTB (or another translation)
resolves PEB.ImageBaseAddress into a valid Apex PE through gdrv3.  First success:
save DTB/module bookkeeping and enable the existing qk_world stage; do not infer
bones from raw physical pages.  h392 is BLOCKED; see _h392_result.md and _v2.txt.