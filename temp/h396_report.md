# h396 — useful transport result and unresolved DTB lookup
## What is now measured (09 Nov 2026 22:38)

The currently installed `gdrv3.sys` has a working second physical-copy endpoint
`IOCTL 0xC3502019`. In `temp/h395_gdrv_map.txt`, this copied the complete requested
pages for two old examples of the former error 1450 as well as current data. The
bytes were observed in a locked user buffer (`4d5a...` at `0x1F9B2B000`). No
injection, driver creation/service restart, host boot/CI change or game write.

`ext/qk_gdrv_mapread.py` wraps this into `g.read_phys` preserving the same
RAM-interval guard used by all physical reads. It gives bytes, not a privileged
address mapping: the destination is a caller-owned locked page. Empty return
information is expected at this ioctl and is not falsely called a mapping.

## What remains unproven

The old `0xC3502014` read still cannot read certain live page-table frames. Do
not use it on those frames. `YCC_TranslateLinsToPhys` (0xC350280C) returned
ERROR_INVALID_FUNCTION on a controlled user-code pointer and on the exported
kernel pointer; it is not a general kernel/game VA read primitive and no 'works'
assertion in that family should be accepted.

The earlier DTB lookup returned no `PID/name/layout` validated EPROCESS on this
live pid; its memory name hits do not prove kernel objects. After substitute
MapK, canonical `qk_va.discover` is still being evaluated with fresh hits. No DTB
or validated Apex VA->PA cache should be claimed from this series before a
fresh `RESULT: dtb=.. base=..` with `SizeOfImage=0xDFB8000` and a repeated PE
read-back is observed. No entity data can be trusted until that happens.

## Cleanup

VM was used in the Windows lab only for paused work (not running code or writing
guest state); no custom ApexDrv started. The controlling gdrv3 process terminates
itself and frees the locked frame on normal return. A malformed earlier process
probe that signalled CPU high has been stopped; no probe remains running. The
VM bench and static experiments are not evidence of process reads through Apex's
anti-cheat. Undetection is never implied merely by 'signed driver'.