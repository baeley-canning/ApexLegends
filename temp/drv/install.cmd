@echo off
rem Run elevated.  Creates a self-signed kernel cert, signs apexr.sys, turns on
rem test signing, installs the service and tries to start it.
rem Test signing only takes effect after a reboot.
setlocal
cd /d "%~dp0"
set LOG=%~dp0install.txt
echo == install start > "%LOG%"
whoami /user >> "%LOG%" 2>&1

echo --- cert >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s='CN=ApexR Test'; $c=Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $s } | Select-Object -First 1; if (-not $c) { $c = New-SelfSignedCertificate -Type CodeSigningCert -Subject $s -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5); Export-Certificate -Cert $c -FilePath 'apexr.cer' | Out-Null; Import-Certificate -FilePath 'apexr.cer' -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null; Import-Certificate -FilePath 'apexr.cer' -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null; 'created ' + $c.Thumbprint } else { 'reused ' + $c.Thumbprint }" >> "%LOG%" 2>&1

echo --- sign >> "%LOG%"
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" sign /v /sm /n "ApexR Test" /fd SHA256 apexr.sys >> "%LOG%" 2>&1
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" verify /v /kp apexr.sys >> "%LOG%" 2>&1

echo --- testsigning >> "%LOG%"
bcdedit /set testsigning on >> "%LOG%" 2>&1
bcdedit /enum {current} | findstr /i "testsigning" >> "%LOG%" 2>&1

echo --- install >> "%LOG%"
copy /y apexr.sys C:\Windows\System32\drivers\apexr.sys >> "%LOG%" 2>&1
sc stop apexr >> "%LOG%" 2>&1
sc delete apexr >> "%LOG%" 2>&1
sc create apexr type= kernel binPath= System32\drivers\apexr.sys start= demand >> "%LOG%" 2>&1
sc start apexr >> "%LOG%" 2>&1
sc query apexr >> "%LOG%" 2>&1
echo == done >> "%LOG%"
type "%LOG%"
