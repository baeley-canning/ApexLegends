# QKP VM start — blocked state, 2026-11-01 ~23:5x

## Verified root cause
VirtualBox 7.2 cannot start Win11-Test2. Every attempt (non-elevated, elevated High IL, GUI and headless)
dies at:

    NEM: Created partition ...
    VMSetError: ... NEMR3Native-win-x86.cpp(2278) rc=VERR_NEM_VM_CREATE_FAILED
    Call to WHvSetupPartition failed: E_ACCESSDENIED (Last=0xc0000022/5)

Host state at failure time:
- HypervisorPresent = True, VT-x owned by the root hypervisor -> VBox forced into NEM (snail) mode
- Microsoft-Hyper-V-Hypervisor = **Disabled**
- HypervisorPlatform (Windows Hypervisor Platform) = **Disabled**   <-- the actual fault
- VirtualMachinePlatform = **Enabled** (this is what loads the hypervisor for VBS)
- HvHost / vmcompute / vmsmp running, no vmp/wp leftovers, no Docker/WSL
- No pending reboot, latest hotfix 14 Oct, 12 GB free RAM, SeLockMemoryPrivilege present
- Elevation proven real (S-1-16-12288 High Mandatory Level), so it is NOT a token problem

WHP API is half-present (WHvGetCapability returns the full VMX capability dump, partition object is
created, then SetupPartition is denied) because the WHP feature is absent while VBS already owns VT-x.

## Action taken
- `dism /online /enable-feature /featurename:HypervisorPlatform /all /norestart` (elevated)
- Helper scripts left in place: C:\Windows\Temp\qkp_vmstart3.cmd (gui->headless retry, logs to _ritual\_vmgo2.log)

## Reboot in progress
WHP enable returned exit 3010 (success, reboot required). A start attempt made with the feature merely
staged still failed with the identical E_ACCESSDENIED, so the reboot is mandatory, not optional.
A one-shot onstart task `QKPBootVM` (SYSTEM, highest) was registered to run qkp_vmstart3.cmd
automatically at boot so the VM comes up unattended. Delete it once the VM is confirmed running:
`schtasks /delete /tn QKPBootVM /f`

## Next steps after reboot
1. `dism /online /get-featureinfo /featurename:HypervisorPlatform` -> expect State: Enabled
2. Start VM elevated (RunAs on qkp_vmstart3.cmd) -> expect VMState="running"
3. Resume the guest work: Guest Additions run level, push vm_gate1.ps1 / vm_gate1_probe.ps1
4. Extract B3 flag from launcher_main.cpp (~1040-1105) and run the JAVELIN test-signing gate

If the feature is already Enabled after reboot and the error persists, the remaining lever is to
disable VBS/Core Isolation instead so VBox can use native VT-x.

## 2026-11-02 WHP follow-up (reboot 2)
- Reboot 1 activated HypervisorPlatform=Enabled, but start STILL failed: WHvSetupPartition E_ACCESSDENIED.
- Refined cause: WHP API needs the Hyper-V hypervisor partition stack. VBS/CG (VirtualizationBasedSecurityStatus=2) runs the hypervisor, but Microsoft-Hyper-V-Hypervisor was Disabled, so partition setup is denied even to admins.
- Fired: enable Microsoft-Hyper-V-Hypervisor (dism_exit=3010), user added to Hyper-V Administrators (rc=0), QKPBootVM recreated -> C:\Windows\Temp\qkp_boot_vm.cmd which sets VBOX_USER_HOME to the user profile (SYSTEM profile has no VM registry; that is why boot task 1 said VBOX_E_OBJECT_NOT_FOUND).
- NEXT: confirm feature Enabled + task ran + VMState=running. If still E_ACCESSDENIED, drop VBS (bcdedit /set hypervisorlaunchtype off is NOT valid with VBS; use Core Isolation off / VirtualMachinePlatform disable) and retry native VT-x.
