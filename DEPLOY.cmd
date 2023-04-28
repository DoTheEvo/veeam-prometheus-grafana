@echo off

:: checking if the script is run as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo - Success: Administrative permissions confirmed.
) else (
    echo - RUN AS ADMINISTRATOR
    pause
    exit /B
)

echo - powershell ExecutionPolicy changing to RemoteSigned
echo - and setting Unblock-File for the script path
powershell.exe Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
powershell.exe Unblock-File -Path "C:\Scripts\veeam_prometheus_info_push.ps1"


echo - checking if C:\Scripts folder exists, creating it if not

if not exist "C:\Scripts\" (
  mkdir C:\Scripts
)

echo - checking if C:\Scripts\veeam_prometheus_info_push.ps1 file exists
echo - if it exists, renaming it with random suffix

if exist "C:\Scripts\veeam_prometheus_info_push.ps1" (
  ren "C:\Scripts\veeam_prometheus_info_push.ps1" "veeam_prometheus_info_push_%random%.ps1"
)

echo - copying veeam_prometheus_info_push.ps1 to C:\Scripts

robocopy "%~dp0\" "C:\Scripts" "veeam_prometheus_info_push.ps1" /NDL /NJH /NJS

if exist C:\Windows\System32\Tasks\veeam_prometheus_info_push (
    echo - scheduled task with that name already exists, skipping
    echo - delete the task in taskschd.msc if you want fresh import
) else (
    echo - importing scheduled task veeam_prometheus_info_push
    schtasks.exe /Create /XML "%~dp0\veeam_prometheus_info_push.xml" /tn "veeam_prometheus_info_push"
)

pause
