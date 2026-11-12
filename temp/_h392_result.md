# h392 stage-0 verdict, 2026-11-09 ~22:00

**BLOCKED.  gdrv3 physical reads work; validated VA->PA translation does not.**

Transport receipt: `temp/_h392_stage0.txt` and `temp/_h392_stage0_v2.txt`,
runner receipt `temp/_h392_run.txt`. PID 14008, gdrv3 STATE 4 before and after.
Nothing was loaded, attached, injected or changed on the host.

1. `qk_stage0_bridge` succeeds at ProcessBasicInformation and returns PEB
   `0x24B000`. That is a query, not a process-memory read. A DTB information class
   experiment was discarded: it did not return a DTB and is not on the product path.
2. The PID-validated EPROCESS/DTB+PEB+PE probe ran twice. Three cached hits did not
   survive layout/PID validation. A fresh, RAM-map-bounded sweep (28,411 MiB,
   454,583 chunks, 6 hits) likewise yielded zero validated candidates. No PE was
   accepted and no DTB was written to the trusted cache.
3. Fresh hit bytes were re-read in `temp/_h392_hits_readback.txt`. A name hit is
   not automatically an EPROCESS. Contexts differ; some were no longer the same
   bytes between sweep and direct read-back. Any successful future candidate still
   needs `Pid`, `ImageFileName`, layout and PE read-back in one consistent chain.
4. Alternate user-read A/B `temp/_h392_access.txt`: OpenProcess with
   QUERY_LIMITED_INFORMATION | VM_READ returned NULL. The query-only PEB handle
   did not imply read permission. No access was elevated or bypassed.
5. Alternate PFN-query A/B returned STATUS_INFO_LENGTH_MISMATCH
   `0xC0000004` (`temp/_h392_mapping.txt`). Raw request/memory evidence is retained,
   but the experimental candidate decoder was removed so nobody mistakes unchecked
   PFN-shaped integers for addresses. It does not supply a working translation.
6. Local static disassembly confirms `0xC3502014` ends in `MmMapIoSpace(pa, len)`;
   this addresses the proposed "pass VA as a PA" idea. The gdrv3 wrapper is not a
   general-purpose VA reader.

The next gate is still translation, not entity offsets. No box, entity enumeration,
player identity, or detection-resistance verdict is derived from h392. In particular,
"raw gdrv3 reads work" is not permission to read guessed physical addresses.