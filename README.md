# WinDots

Fully reproducible and scripted Windows installation, because I got sick of reinstalling Windows. Using NTLite and PowerShell scripts, no MDT or Configuration Manager.

## Creating a New Windows ISO

### NTLite Steps

1. Download a Windows 11 IoT Enterprise LTSC 2024 ISO from massgrave: https://massgrave.dev/windows_ltsc_links

2. Open NTLite. Image tab > Add > "Image (ISO, WIM, ESD, SWM)". Select the Windows 11 LTSC ISO you just downloaded.

3. Mount the Windows 11 IOT Enterprise LTSC index.

4. Download the NTLitePreset.xml file from the root of this repo. In NTLite, click the Preset tab > Import. Select the downloaded xml preset. Double click the preset from the Preset menu to apply it.

5. In the left hand menu in NTLite, click Updates. In the Toolbar tab, click Add > Template > .NET Framework 3.5.

6. In NTLite, Add > Latest online updates. Check the following items:

   **Cumulative update:**
   - The latest cumulative update

   **.NET Framework:**
   - The latest .NET Framework 3.5 and 4.8.1 cumulative update

   **Apps & features:**
   - Windows Package Manager (App Installer, WinGet)
   - Microsoft.UI.Xaml v2.8
   - Microsoft Visual C++ UWP Desktop Runtime Package (Microsoft.VCLibs.140.00.UWPDesktop)
   - Microsoft Visual C++ UWP Runtime Package (Microsoft.VCLibs.140.00.UWPDesktop)
   - Windows App Runtime (Microsoft.WindowsAppRuntime.1.8)
   - Windows App Runtime 2 (Microsoft.WindowsAppRuntime.2.2.0)
   - Windows Terminal

   Everything else can be unchecked. Click Download, wait for all selected items to download, then click Enqueue.

7. Navigate to https://store.rg-adguard.net to download several packages. Change the first dropdown to ProductId and the other dropdown to Retail. Enter the following ProductIds into the text field and click the checkmark to load results. Download the latest .msixbundle/.appxbundle for each app.
   - Calculator: 9wzdncrfhvn5
   - Notepad: 9msmlrh6lzf3
   - Snipping Tool: 9mz95kl8mr0l
   - Scan: 9wzdncrfj3pv

8. In NTLite, Add > Package files > select all 4 downloaded packages to add them. Change the "Clean update backup" option in the ribbon to "DISM ResetBase".

9. In the left hand menu in NTLite, click Apply. Set these options:
   - Saving mode: Save the image and trim editions.
   - Image format: Standard, editable (WIM).
   - Options: Create ISO > Select where you want the ISO to be saved and give it a name.
   - In the ribbon, click Process.

### Run the Script on the ISO

1. After NTLite creates your Windows ISO, open Windows Terminal as admin and run this command to run the script on this repo:

   ```powershell
   iwr -useb https://raw.githubusercontent.com/taylorstools/windots/main/New-WinDotsISO.ps1 | iex
   ```