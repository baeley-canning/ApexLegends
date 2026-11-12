# Restore last saved working boot once, no kernel state changes on the host.
# The bench only queries PID of existing drivers and performs reads in the VM.
$vb='C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm='Win11-Test2'
& $vb controlvm $vm poweroff | Out-Null
Start-Sleep -Seconds 3
& $vb snapshot $vm restore pre_h394_v16_read | Out-Null
& $vb discardstate $vm | Out-Null
& $vb startvm $vm --type gui
"VM restore/coldboot requested at $(Get-Date -Format o)" | Set-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h395_vm.txt'