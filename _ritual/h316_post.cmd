@echo off
rem logon trigger for the h316 host run: fires once after a bugcheck reboot (armed by h316_run.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0h316_post.ps1"
