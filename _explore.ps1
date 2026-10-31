$ErrorActionPreference = 'Continue'
$sb = [System.Text.StringBuilder]::new()
function L($s){ $sb.AppendLine($s) | Out-Null }
try { Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\generated_cheats' -Force | ForEach-Object { L ("GEN " + $_.Name) } } catch { L ("GEN ERR " + $_.Exception.Message) }
L "---PHASE5---"
try { Get-ChildItem -Recurse -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\phase5_cpp_imgui' -Force | ForEach-Object { L ("P5 " + $_.FullName.Replace('c:\Users\New User\OneDrive\Desktop\cheating\\','')) } } catch { L ("P5 ERR " + $_.Exception.Message) }
L "---SEARCH---"
try { Get-ChildItem -Recurse -Path 'c:\Users\New User\OneDrive\Desktop\cheating' -Filter 'apex_cheat.sln' -ErrorAction SilentlyContinue | ForEach-Object { L ("SLN " + $_.FullName) } } catch {}
L "---DONE---"
$sb.ToString() | Out-File -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_out.txt' -Encoding ascii
