@echo off
rem logon trigger for the split h317 run (armed by h317_arm.ps1, fires only after a bugcheck reboot)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0h317_post.ps1"
