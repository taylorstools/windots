@echo off
setlocal enabledelayedexpansion
wpeinit

:: Find drive letters
for %%a in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%a:\setup-custom.exe set RAMDRIVE=%%a
    if exist %%a:\sources\boot.wim set USBDRIVE=%%a
)

:: Launch Windows Setup
!RAMDRIVE!:\setup-custom.exe /Unattend:!USBDRIVE!:\autounattend.xml /NoReboot

:: Find drive letter Windows installed to
for %%a in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%a:\Windows\explorer.exe set SYSTEMDRIVE=%%a
)

:: Disable the creation of 8.3 file names on Windows volume
fsutil.exe 8dot3name set !SYSTEMDRIVE!: 1

:: Remove the existing 8.3 file names
fsutil.exe 8dot3name strip /s /f !SYSTEMDRIVE!:\

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