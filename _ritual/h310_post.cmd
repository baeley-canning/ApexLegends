@echo off
rem logon trigger for the h310 host run: fires once after the bugcheck reboot, deletes itself
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0h310_post.ps1"
