# q.ps1 -- atomically enqueue a job into the p64 listener queue.
# Same-directory rename on NTFS is metadata-only, so the listener only ever sees a
# complete cmd.txt or none at all.  NEVER Copy-Item straight onto cmd.txt.
param([Parameter(Mandatory=$true)][string]$Job)
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$cmd  = Join-Path $root 'temp\cmd.txt'
$tmp  = Join-Path $root 'temp\cmd.new'
if (-not (Test-Path -LiteralPath $Job)) { throw "job file missing: $Job" }
Copy-Item -LiteralPath $Job -Destination $tmp -Force
Start-Sleep -Milliseconds 150
if (-not (Test-Path -LiteralPath $cmd)) {
    Move-Item -LiteralPath $tmp -Destination $cmd
} else {
    # replace: delete then rename (listener tolerates a brief absence)
    Remove-Item -LiteralPath $cmd -Force
    Move-Item -LiteralPath $tmp -Destination $cmd
}
'QUEUED ' + (Get-Date -Format HH:mm:ss) + ' <- ' + (Split-Path -Leaf $Job)
