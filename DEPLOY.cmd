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
powershell.exe Set-ExecutionPolicy -ExecutionPolicy RemoteSigned

echo - copying veeam_prometheus_info_push.ps1 in to C:\Scripts\
if not exist "C:\Scripts\" mkdir C:\Scripts
robocopy "%~dp0\" "C:\Scripts" "veeam_prometheus_info_push.ps1" /NDL /NJH /NJS

:: importing scheduled task, will not overwrite
:: delete the task in taskschd.msc if you want fresh import

if exist C:\Windows\System32\Tasks\veeam_prometheus_info_push (
    echo - scheduled task with that name already exists, skipping
) else (
    schtasks.exe /Create /XML "%~dp0\veeam_prometheus_info_push.xml" /tn "veeam_prometheus_info_push"
)

pause
