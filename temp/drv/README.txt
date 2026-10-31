apexr - how to finish the setup
================================

State as of the last check (all verified, no reboot done yet):
  Secure Boot ........ False            (Confirm-SecureBootUEFI)
  testsigning ........ Yes in BCD       (takes effect on next boot)
  cert CN=ApexR Test . in Root + Trusted Publishers
  apexr.sys .......... C:\Windows\System32\drivers\apexr.sys (5488 bytes, sig Valid)
  service ............ apexr, DEMAND_START, currently STOPPED (577 until reboot)
  client ............. kx.py (selftest + "Coupe" scan), run_kx.bat runner

Why 577 right now: the testsigning flag is read once by the loader at boot, so
even with Secure Boot off the driver cannot start until you reboot.

Sequence
--------
1. Reboot.
2. Start Apex (r5apex_dx12.exe) as usual.
3. Double-click  drv\after_reboot.bat        (self-elevates, waits up to 15 min
                                              for the game, then selftests)
   Expect in drv\after_reboot.txt:
     STATE : 4 RUNNING
     image base=0x.... size_image=0x.... sections=.. machine=0x8664
     pdb=<...r5apex...>.pdb
     selftest PASS - parsed the target's PE headers over IOCTL 0x222000
     baseline OpenProcess(VM_READ) failed err=5  -> EAC stripped it
     (or baseline ReadProcessMemory ok=False err=299 -- also proof the
      user-mode path is blocked while the driver path works)
4. Full string scan:   drv\after_reboot.bat scan
   (same script with the "scan" arg; results land in temp\kx.txt)
   Or run it by hand:  run_kx.bat            -> kx_console.txt / kx.txt
                       run_kx.bat --name Foo --pid 0x1234

Revert
------
  bcdedit /set testsigning off          (as admin, then reboot)
  sc stop apexr & sc delete apexr
  certutil -delstore Root "ApexR Test"
  certutil -delstore TrustedPublisher "ApexR Test"
  then re-enable Secure Boot in the BIOS if you want it back.

Notes
-----
* testsigning shows a desktop watermark and lets any test-signed driver load;
  if EAC refuses the session after the reboot, that is the trade-off, not a bug
  in the driver.
* The driver only exposes two IOCTLs (0x222000 read, 0x222004 VAD query) and
  is DEMAND_START, so it is not loaded unless you start it.
