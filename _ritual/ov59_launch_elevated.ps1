# ov58_launch_elevated.ps1 - runs the launcher ELEVATED and captures its console.
#
# Needed because Start-Process cannot combine -Verb RunAs with
# -RedirectStandardOutput (PS 5.1).  This wrapper is what gets started with the
# UAC prompt; it does the redirection itself, so the elevated ladder's own
# verdicts are readable afterwards instead of vanishing with the console window.
param([int] $Pid_ = 0, [string] $Method = 'manual',
      [string] $Out = 'C:\h320x\t287_launch.txt')

$exe = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apex_launcher.exe'
"elevated launcher wrapper - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  (append mode)" |
    Add-Content -LiteralPath $Out -Encoding UTF8
"elevated : $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" |
    Add-Content -LiteralPath $Out
# 'ladder' = no --method flag: the sticky rung runs first and the ladder falls
# through A4 -> A3 -> A2 -> A1 instead of stopping at the first failure.
if ($Method -eq 'ladder') { & $exe --inject "--pid=$Pid_" *>> $Out }
else                      { & $exe --inject "--method=$Method" "--pid=$Pid_" *>> $Out }
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $Out
