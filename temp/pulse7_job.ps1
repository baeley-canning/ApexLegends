# pulse7_job - delayed truth-extractor (one-shot)
Start-Sleep -Seconds 165
$o='C:\Users\New User\OneDrive\Desktop\cheating\temp\pulse7.txt'
('TIME='+$(Get-Date -Format HH:mm:ss)) | Set-Content $o
$f=Get-Item 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_feed.json' -EA SilentlyContinue
if($f){ ('FEED SIZE='+$f.Length+' AGE_S='+[math]::Round(((Get-Date)-$f.LastWriteTime).TotalSeconds,1)) | Add-Content $o }
else{ 'FEED=NONE_YET' | Add-Content $o }
('PROD11932='+[bool](Get-Process -Id 11932 -EA SilentlyContinue)) | Add-Content $o
('-- EMIT_TAIL --') | Add-Content $o
Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\emit_out2.txt' -Tail 6 -EA SilentlyContinue | Add-Content $o
('-- EVENTS --') | Add-Content $o
Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\watch_events.log' -EA SilentlyContinue | Add-Content $o
'DONE' | Add-Content $o
