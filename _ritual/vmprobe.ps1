$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\vmprobe.txt'
function S($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Try-S($l, $b) { S "--- $l ---"; try { S (& $b) } catch { S ("  ERR " + $_.Exception.Message) }; S '' }

S ("vmprobe " + (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
Try-S 'list vms' { & $VB list vms 2>&1 }
Try-S 'list hostinfo (cpu/ram/vtx)' { (& $VB list hostinfo 2>&1) | Select-String -Pattern 'Host time|Processor|Memory size|Virtualization' }
Try-S 'list hdds' { & $VB list hdds 2>&1 }
Try-S 'snapshots Win11-Test2' { & $VB snapshot 'Win11-Test2' list --machinereadable 2>&1 }
Try-S 'showvminfo Win11-Test2 (key fields)' {
    (& $VB showvminfo 'Win11-Test2' --machinereadable 2>&1) |
      Select-String -Pattern '^(name|OSType|memory|cpus|VMState|firmware|snapshotFolder|vrde|nestedpaging|GuestMemoryBalloon|SharedFolder.*|SATA|IDE|nic|macaddress|graphicscontroller|accelerate3d|cpu-profile|VirtEx|VT-x|paravirtprovider|hpet|firmware)' }
Try-S 'vm folder contents' {
    Get-ChildItem 'C:\Users\New User\VirtualBox VMs' -Recurse -Depth 2 -EA 0 |
      ForEach-Object { '{0,12}  {1}' -f $_.Length, $_.FullName } }
Try-S 'guest additions iso' { Test-Path 'C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso' }
Try-S 'Win11-Test registered?' { Select-String -Path "$env:USERPROFILE\.VirtualBox\VirtualBox.xml" -Pattern 'MachineEntry' }
S '--- end ---'
