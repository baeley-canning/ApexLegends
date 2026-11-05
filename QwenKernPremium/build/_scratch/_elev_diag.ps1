# build\_elev_diag.ps1
#
# Why did Start-Process -Verb RunAs hand back a PID but produce no file?
# A2: same route, payload = cmd.exe writing to C:\ProgramData (world-writable),
#     and we inspect HasExited/ExitCode to tell "child died" from "child never ran".
# C : scheduled task via the Task Scheduler COM objects (no /tr quoting).

$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$log  = Join-Path $root 'build\_elev_diag.txt'
$probe = 'C:\ProgramData\_qwen_elev_probe.txt'
function Add([string] $t) { $t | Out-File -FilePath $log -Encoding utf8 -Append }

'== diag ' + (Get-Date -Format 'HH:mm:ss') + ' ==' | Out-File -FilePath $log -Encoding utf8
Remove-Item $probe -ErrorAction SilentlyContinue

# --- what happened to route A's pid ---------------------------------------
try {
    $old = Get-Process -Id 21288 -ErrorAction Stop
    Add ("A-pid 21288 alive, start=" + $old.StartTime)
} catch {
    Add "A-pid 21288 gone"
}
Add ("probe-exists(before)=" + (Test-Path $probe))

# --- A2: cmd payload, observable exit --------------------------------------
try {
    $p = Start-Process -FilePath 'cmd.exe' -Verb RunAs -PassThru -ErrorAction Stop `
        -ArgumentList '/c', ('whoami /groups > "{0}" 2>&1' -f $probe)
    Start-Sleep -Seconds 6
    Add ("A2 pid=" + $p.Id + " hasExited=" + $p.HasExited)
    if ($p.HasExited) { Add ("A2 exitcode=" + $p.ExitCode) }
} catch {
    Add ("A2 EXCEPTION " + $_.Exception.Message)
}
Add ("A2 probe-exists=" + (Test-Path $probe))

# --- C: Task Scheduler COM ------------------------------------------------
try {
    $svc  = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $folder = $svc.GetFolder('\')
    $def = $svc.NewTask(0)
    $def.RegistrationInfo.Description = 'QwenKern elevation probe'
    $def.Settings.ExecutionTimeLimit = 'PT5M'
    $def.Settings.DisallowStartIfOnBatteries = $false
    $def.Settings.StopIfGoingOnBatteries     = $false
    # 3 = TASK_LOGON_INTERACTIVE_TOKEN, 0 = TASK_RUNLEVEL_LUA -> use LEAST? we want HIGHEST
    $def.Principal.RunLevel = 1          # TASK_RUNLEVEL_HIGHEST
    $def.Principal.LogonType = 3          # TASK_LOGON_INTERACTIVE_TOKEN
    $action = $def.Actions.Create(0)      # TASK_ACTION_EXEC
    $action.Path = 'powershell.exe'
    $action.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'build\_elev_test.ps1')
    $null = $folder.RegisterTaskDefinition('QwenKernElevProbe', $def, 6, $null, $null, 3)
    Add 'C: registered'
    $null = $folder.GetTask('QwenKernElevProbe').Run($null)
    Add 'C: started'
} catch {
    Add ("C: EXCEPTION " + $_.Exception.Message)
}
Start-Sleep -Seconds 15
$t = Join-Path $root 'build\_elev_test.txt'
Add ("C: output-file=" + (Test-Path $t))
if (Test-Path $t) { Add ('C: content -> ' + ((Get-Content $t) -join ' | ')) }
Add 'diag done'
