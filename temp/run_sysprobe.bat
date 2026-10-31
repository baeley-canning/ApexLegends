@echo off
cd /d "C:\Users\New User\OneDrive\Desktop\cheating"
"C:\Users\New User\OneDrive\Desktop\cheating\aiaimbot\.venv\Scripts\python.exe" "C:\Users\New User\OneDrive\Desktop\cheating\temp\sysprobe.py" %* > "C:\Users\New User\OneDrive\Desktop\cheating\temp\sysprobe_console.txt" 2>&1
echo exit=%ERRORLEVEL% >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\sysprobe_console.txt"
