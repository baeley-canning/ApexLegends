@echo off
echo START %DATE% %TIME% > "C:\Users\Public\h307_elevated.txt"
whoami >> "C:\Users\Public\h307_elevated.txt"
whoami /groups | findstr /i "Mandatory" >> "C:\Users\Public\h307_elevated.txt"
copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h307_MEMORY.DMP >> "C:\Users\Public\h307_elevated.txt" 2>&1
echo COPY-RC=%ERRORLEVEL% >> "C:\Users\Public\h307_elevated.txt"
