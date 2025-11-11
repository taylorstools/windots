@echo off

:: Check there is an Internet connection, if not, loop until there is one
:CHECK_CONNECTION
ping -n 1 google.com >nul 2>&1
if errorlevel 1 (
    echo No Internet connection detected.
    echo Connect to a network. Checking again in 5 seconds...
    timeout /t 4 >nul 2>&1
    cls
    timeout /t 1 >nul 2>&1
    goto CHECK_CONNECTION
)

if not exist "C:\PostInstall" (
    mkdir "C:\PostInstall"
)

:: URL of the post-install script on GitHub
set "URL=https://raw.githubusercontent.com/taylorstools/windots/refs/heads/main/postinstall/Run-PostInstallScript.ps1"

:: Where the script will be downloaded to
set "SCRIPT=C:\PostInstall\Run-PostInstallScript.ps1"

:: Set %POWERSHELL% to full path
set "POWERSHELL=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

:: Download the post-install script
%POWERSHELL% -NoProfile -ExecutionPolicy Bypass -Command ^
    "Invoke-WebRequest -Uri '%URL%' -OutFile '%SCRIPT%'"

:: Run the script if it exists
if exist "%SCRIPT%" (
    %POWERSHELL% -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process %POWERSHELL% -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%SCRIPT%\"' -Verb RunAs"
    exit /b 0
) else (
    echo Failed to download post-install script.
    echo(
    pause
    exit /b 1
)
