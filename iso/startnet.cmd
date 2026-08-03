@echo off
setlocal enabledelayedexpansion
wpeinit

:: Find USB drive letter
for %%a in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%a:\sources\boot.wim set USBDRIVE=%%a
)

:: Prompt for Wi-Fi credentials
setlocal DisableDelayedExpansion
set "WifiSsid="
set "WifiPassword="

:AskWifi
set "Response="
set /p "Response=Connect this PC to Wi-Fi automatically after Windows install? (Y/N): "
if /i "%Response%"=="N" goto EndWifiPrompt
if /i not "%Response%"=="Y" goto AskWifi
echo(

:GetSsid
set /p "WifiSsid=  Network name (SSID): "
if not defined WifiSsid goto GetSsid

:GetPassword
set /p "WifiPassword=  Password: "
if not defined WifiPassword goto GetPassword

setlocal EnableDelayedExpansion
md "%SystemDrive%\Windows\Temp" 2>nul
<nul set /p "=!WifiSsid!" > "%SystemDrive%\Windows\Temp\SSID.txt"
<nul set /p "=!WifiPassword!" > "%SystemDrive%\Windows\Temp\Password.txt"
endlocal

:EndWifiPrompt
endlocal

:: Launch Windows Setup
%SystemDrive%\setup-windots.exe /Unattend:!USBDRIVE!:\autounattend.xml /NoReboot

:: Find drive letter Windows installed to
for %%a in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%a:\Windows\explorer.exe set OSDRIVE=%%a
)

:: Disable the creation of 8.3 file names on Windows volume
fsutil.exe 8dot3name set !OSDRIVE!: 1

:: Remove the existing 8.3 file names
fsutil.exe 8dot3name strip /s /f !OSDRIVE!:\

:: Stage Wi-Fi credentials on the installed OS
if exist "%SystemDrive%\Windows\Temp\SSID.txt" (
    md "!OSDRIVE!:\WinDots\WiFiCredentials" 2>nul
    move /y "%SystemDrive%\Windows\Temp\SSID.txt" "!OSDRIVE!:\WinDots\WiFiCredentials\" >nul
    move /y "%SystemDrive%\Windows\Temp\Password.txt" "!OSDRIVE!:\WinDots\WiFiCredentials\" >nul
)

echo(
echo ============================================
echo ====== WINDOWS INSTALLATION COMPLETE! ======
echo ============================================
echo(
echo Rebooting in 5 seconds.

:: Timeout in WinPE
ping -n 6 127.0.0.1 >nul 2>&1

:: Reboot
wpeutil reboot