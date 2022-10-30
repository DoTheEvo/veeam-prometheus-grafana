:: allows powershell scripts
:: copies ps1 script file to c:\Scripts
:: creates scheduled task to execute every hour

@echo off

:: check if the script is run as administrator

net session >nul 2>&1
if %errorLevel% == 0 (
    echo Success: Administrative permissions confirmed.
) else (
    echo RUN AS ADMINISTRATOR
    pause
    exit /B
)

powershell.exe Set-ExecutionPolicy -ExecutionPolicy RemoteSigned

if not exist "C:\Scripts\" mkdir C:\Scripts

robocopy "%~dp0\" "C:\Scripts" "veeam_prometheus_info_push.ps1"

:: import scheduled task
schtasks.exe /Create /XML "%~dp0\veeam_prometheus_info_push.xml" /tn "veeam_prometheus_info_push"

pause

