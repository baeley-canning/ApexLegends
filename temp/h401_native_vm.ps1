# Native process image VAs to guide the DTB walk, with no app/game writes.
$p=Start-Process -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\qk_process_query.exe' `
    -ArgumentList '--pid','14624' -Verb RunAs -Wait -PassThru -RedirectStandardOutput 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h401_native_vm.txt'
Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h401_native_vm.txt' -First 8