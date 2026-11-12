@echo off
copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h298_MEMORY.DMP >nul 2>&1
whoami /groups > C:\Users\Public\h298_elevated.txt 2>&1
