_attic_apexdrv/ — apexdrv retired 19/11 (gdrv3-only transport decision)
=======================================================================

WHY: apexdrv's per-IOCTL KeStackAttachProcess is the only variable that
correlated with the two EAAC game terminations on 07/11 (2/2 kills after
attach-shaped reads). gdrv3 (vendor GIOV3) swept 9 GB of physical RAM with
ZERO Javelin events. Product transport is now strictly gdrv3
(usermode RPM ruled out separately: error 87, h413-h415, 18/11).

Everything here is MOVED, not copied. Restore = copy back to the same
relative path (tree below mirrors QwenKernPremium\). The ApexDrv service
entry (stopped, binPath \??\C:\apexdrv.sys) predates this archive and is
untouched by it; remove it only with the user's say-so.

MANIFEST (captured immediately before the move, SHA256 first 16 hex):

  QwenKernPremium\driver\apexdrv.c              | 108491 B | sha256:5E1CCEE30A38BF59
  QwenKernPremium\include\apex_driver_ioctl.h   |  28469 B | sha256:EC8185F65AF1C292
  QwenKernPremium\build\apexdrv.sys             |  20480 B | sha256:A303EFB3AD268DF5
  QwenKernPremium\build\apexdrv_v2_9B119FD0.sys |  10152 B | sha256:9B119FD0C38740A2  (k9-proven build)
  QwenKernPremium\build\apexdrv_v13_E906CEE9.bak|  17920 B | sha256:E906CEE97B9927F4
  QwenKernPremium\build\apexdrv_dev.cer         |    806 B | sha256:1A357DD521C8CA1D
  QwenKernPremium\build\apexdrv.obj             |  43376 B | sha256:3B01AC5FAB028725
  QwenKernPremium\driver\apexdrv.obj            |  43376 B | sha256:C6B96F52B8C2CE27

Pre-move evidence file: temp\p_arch_manifest_pre.txt.

NOT moved (deliberately):
  - QwenKernPremium\driver\apexdrv.vcxproj          (build glue; harmless, referenced
                                                     by BuildDriver.ps1 filters)
  - QwenKernPremium\**\build\obj\apexdrv\**         (regenerable MSVC intermediates/logs)
  - QwenKernPremium\build\_scratch\*probe/ioctl*.txt(historical evidence snapshots)

Known legacy scripts that still reference apexdrv and are LEFT AS-IS
(dormant unless invoked): s2_stage_v14.ps1, sc5.ps1, sig2.ps1, st2.ps1,
st3.ps1, t1_transport.ps1, t7_tidy.ps1, _probe5.ps1, _probe6.ps1,
_psctest.ps1, _start3.ps1. They touch services/DSE — any future revival
must go VM-first per AGENTS.md R1.

Restore procedure (exact inverse):
  Copy-Item _attic_apexdrv\driver\*   QwenKernPremium\driver\
  Copy-Item _attic_apexdrv\include\*  QwenKernPremium\include\
  Copy-Item _attic_apexdrv\build\*    QwenKernPremium\build\
then re-verify SHA256 against the manifest above before loading ANYTHING.
