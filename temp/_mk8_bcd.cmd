@echo off
rem h34u: does the BCD bad-page list cover the dead PFNs? (read-only)
set F=C:\Users\New User\OneDrive\Desktop\cheating\temp\_mk8_bcd.txt
echo === %TIME% === > "%F%"
echo --- {badmemory} --- >> "%F%"
bcdedit /enum {badmemory} >> "%F%" 2>&1
echo --- {current} --- >> "%F%"
bcdedit /enum {current} >> "%F%" 2>&1
