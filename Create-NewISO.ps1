Write-Host "Test" | Out-Null
$Host.UI.RawUI.WindowTitle = "Windots Windows ISO Creation"
$Host.UI.RawUI.BackgroundColor = "black"
#Clear-Host

#region Functions

#Function to download files from the Windots GitHub repo
function Save-GitHubFiles {
    param (
        [string[]]$Files,
        [string]$DownloadDirectory
    )

    #The GitHub repo where the files are
    $Repo = "taylorstools/windots"

    #For each file in the $Files array
    foreach ($File in $Files) {
        #Set the download URL
        $Download = "https://raw.githubusercontent.com/$Repo/main/$File"

        #Create the folder for files to download to
        if (-not (Test-Path -Path "$DownloadDirectory")) {
            New-Item -Path $DownloadDirectory -ItemType Directory | Out-Null
        }

        #Make it so that filename of download is only everything after the last /
        $File = $File -replace ".*/", ""

        #Download file(s)
        & {
            $ProgressPreference = "SilentlyContinue"
            Invoke-WebRequest -Uri $Download -OutFile "$DownloadDirectory\$File"
        }
    }
}

#Function to open file picker to select files
function Get-FileName ($InitialDirectory) {
    Add-Type -AssemblyName System.Windows.Forms
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.InitialDirectory = $initialDirectory
    $OpenFileDialog.Filter = "ISO Files (*.iso)|*.iso"
    $OpenFileDialog.Multiselect = $false #Ensure only one file can be selected
    $Result = $OpenFileDialog.ShowDialog()
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $OpenFileDialog.FileName
    } else {
        return $null #Return null if no file is selected
    }
}

#endregion Functions

#region User Input

#Have user select their Windows 11 ISO
Write-Host "Select your NTLite Windows 11 .ISO file..." -ForegroundColor Black -BackgroundColor Yellow
Start-Sleep 2

$WindowsISO = $null

do {
    $WindowsISO = Get-FileName -InitialDirectory "$env:USERPROFILE\Downloads"

    if ($WindowsISO) {
        ""
        Write-Host "Selected Windows 11 ISO file: $WindowsISO"
    } else {
        ""
        $userChoice = Read-Host "No file selected. Do you want to try again? (Y/N)"
        if ($userChoice -ne "Y") {
            ""
            Write-Host "No Windows 11 ISO file selected. Exiting..."
            ""
            pause
            exit
        }
    }
} while (-not $WindowsISO)

#endregion User Input

#region Getting Started

""
#Cleanup stale wims if any are mounted
Write-Host -ForegroundColor DarkGray "Cleaning up any stale mounted images..."
dism /cleanup-wim

""
#Create directories
Write-Host -ForegroundColor DarkGray "Creating scratch directories..."
if (Test-Path -Path "C:\ScratchDir") {
    Remove-Item "C:\ScratchDir" -Recurse -Force
}
$ScratchDir = (New-Item -Path "C:\ScratchDir" -ItemType Directory -Force).FullName
$ExtractedISO = (New-Item -Path "$ScratchDir\Extracted" -ItemType Directory -Force).FullName #Where Windows .iso will be extracted to
$Workspace = (New-Item -Path "$ScratchDir\Offline" -ItemType Directory -Force).FullName #Where install.wim will be mounted to
$BootWorkspace = (New-Item -Path "$ScratchDir\BootWorkspace" -ItemType Directory -Force).FullName #Where boot.wim will be mounted to

#Install 7-Zip if it's not installed
if (!(Test-Path -Path "$env:ProgramFiles\7-Zip\7z.exe")) {
    ""
    Write-Host -ForegroundColor DarkGray "Installing 7-Zip..."

    #Install 7-Zip
    winget install --accept-source-agreements --accept-package-agreements --id=7zip.7zip -e
}

""
#Use 7-Zip to extract Windows ISO
Write-Host -ForegroundColor DarkGray "Extracting Windows ISO to scratch directory: $ExtractedISO..."
& ${env:ProgramFiles}\7-Zip\7z.exe x $WindowsISO "-o$($ExtractedISO)" -y 2> $null | Out-Null

#Determine if install.wim or install.esd
if (Test-Path -Path "$ExtractedISO\sources\install.wim") {
    $InstallWIM = "$ExtractedISO\sources\install.wim"
}
    elseif (Test-Path -Path "$ExtractedISO\sources\install.esd") {
        $InstallWIM = "$ExtractedISO\sources\install.esd"
    }

#Get build info and number for naming resulting ISO
$OSInfo = Get-WindowsImage -ImagePath "$InstallWIM" -Index 1
$OSNameandBuild = $OSInfo.ImageName + " " + $OSInfo.Version
#Get date
$Date = Get-Date -Format "MM-dd-yy"

#endregion Getting Started

#region Mount install.wim and modify

#Mount install.wim
""
Write-Host -ForegroundColor DarkGray "Mounting $InstallWIM to $Workspace..."
Mount-WindowsImage -ImagePath "$InstallWIM" -Path "$Workspace" -Index 1

Write-Host -ForegroundColor DarkGray "Applying default app associations..."
#Copy default apps XML
Save-GitHubFiles -Files @("iso/AppAssociations.xml") -DownloadDirectory "$ScratchDir"

#Import default apps XML
Dism /Image:$Workspace /Import-DefaultAppAssociations:$ScratchDir\AppAssociations.xml

""
Write-Host -ForegroundColor DarkGray "Disabling UAC..."
""
#Load registry hive
reg load HKLM\WIN11OFFLINE $Workspace\Windows\System32\Config\SOFTWARE
#Disable UAC
reg.exe add "HKLM\WIN11OFFLINE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableLUA" /t REG_DWORD /d 0 /f
reg.exe add "HKLM\WIN11OFFLINE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d 0 /f
reg.exe add "HKLM\WIN11OFFLINE\Microsoft\Windows\CurrentVersion\Policies\System" /v "PromptOnSecureDesktop" /t REG_DWORD /d 0 /f
#Unload registry hive
reg unload HKLM\WIN11OFFLINE

#Download script to shell:common startup
Save-GitHubFiles -Files @("iso/Download-PostInstallScript.bat") -DownloadDirectory "$Workspace\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"

""
Write-Host -ForegroundColor DarkGray "Cleaning up C:\ folders on wim..."
$Folders = @(
    "AMD",
    "Config.msi",
    "Dell",
    "HPIALogs",
    "HP",
    "inetpub",
    "Intel",
    "PerfLogs",
    "ProgramFilesFolder",
    "PwrMgmt",
    "SWSetup",
    "system.sav",
    "Windows.old"
)

foreach ($Folder in $Folders) {
    if (Test-Path -Path "$Workspace\$Folder") {
        Remove-Item "$Workspace\$Folder" -Recurse -Force
    }
}

""
Write-Host -ForegroundColor DarkGray "Saving changes and unmounting $InstallWIM..."
#Dismount Image
Dismount-WindowsImage -Path $Workspace -Save

#Remove workspace folder
Remove-Item $Workspace -Recurse -Force

#endregion Mount install.wim and modify

#region Export Windows Setup index from boot.wim

#Export the Microsoft Windows Setup index from the boot.wim
Write-Host -ForegroundColor DarkGray "Exporting just the Windows Setup index from the Windows ISO boot.wim..."

#Get index # of boot.wim
$BootIndex = (Get-WindowsImage -ImagePath "$ExtractedISO\sources\boot.wim" | Where-Object { $_.ImageName -like "*Microsoft Windows Setup*" }).ImageIndex
dism /export-image /SourceImageFile:"$ExtractedISO\sources\boot.wim" /SourceIndex:$BootIndex /DestinationImageFile:"$ScratchDir\boot.wim" /Compress:max /CheckIntegrity

#endregion Export Windows Setup index from boot.wim

#region Mount boot.wim and modify

""
#Modify boot.wim
Write-Host -ForegroundColor DarkGray "Mounting $ScratchDir\boot.wim to $BootWorkspace..."
""
Mount-WindowsImage -ImagePath "$ScratchDir\boot.wim" -Path "$BootWorkspace" -Index 1

Write-Host -ForegroundColor DarkGray "Renaming setup.exe inside Windows Setup..."
#Rename setup.exe in boot.wim
Rename-Item -Path "$BootWorkspace\setup.exe" -NewName "setup-custom.exe"

#Copy startnet.cmd to $BootWorkspace\Windows\System32
$Startnet = "$BootWorkspace\Windows\System32\startnet.cmd"
if (Test-Path -Path "$Startnet") { Remove-Item "$Startnet" -Force }
Save-GitHubFiles -Files @("iso/startnet.cmd") -DownloadDirectory "$BootWorkspace\Windows\System32"

""
Write-Host -ForegroundColor DarkGray "Saving changes and unmounting modified boot.wim..."
#Dismount Image
Dismount-WindowsImage -Path $BootWorkspace -Save

#Remove Workfolder
Remove-Item $BootWorkspace -Recurse -Force

#Copy modified wim to extracted ISO directory
Write-Host -ForegroundColor DarkGray "Replacing stock boot.wim with modified one in extracted Windows ISO directory: $ExtractedISO..."
Remove-Item "$ExtractedISO\sources\boot.wim" -Force
Move-Item -Path "$ScratchDir\boot.wim" -Destination "$ExtractedISO\sources\boot.wim"

#endregion Mount boot.wim and modify

#region Create ISO

""
#Download autounattend file
Save-GitHubFiles -Files @("iso/autounattend.xml") -DownloadDirectory "$ExtractedISO"

#Download oscdimg
Save-GitHubFiles -Files @("iso/oscdimg.exe") -DownloadDirectory "$ScratchDir"

#Directory ISO file will be saved to
$Dir = "$env:USERPROFILE\Desktop"
#Construct file name
$ISOName = "WinDots $OSNameandBuild $Date"
#Construct full path to ISO file
$ISOPath = "$Dir\$ISOName.iso"
$Counter = 2
#Construct a different ISO path if file already exists
while (Test-Path -Path $ISOPath) {
    $ISOPath = Join-Path $Dir ("$ISOName $Counter.iso")
    $Counter++
}

Write-Host -ForegroundColor DarkGray "Creating ISO..."
$oscdimgCommand = "$ScratchDir\oscdimg.exe -m -o -u2 -udfver102 -bootdata:2#p0,e,b$ExtractedISO\boot\etfsboot.com#pEF,e,b$ExtractedISO\efi\microsoft\boot\efisys.bin $ExtractedISO `"$ISOPath`""
Start-Process "cmd.exe" -ArgumentList "/c `"$oscdimgCommand`"" -Wait

""
Write-Host -ForegroundColor DarkGray "ISO successfully created at $ISOPath."

""
Write-Host -ForegroundColor DarkGray "Cleaning up..."
#Remove WIMPrep Folder
Remove-Item $ScratchDir -Recurse -Force

""
Write-Host -ForegroundColor Green "Done."
""

pause

#endregion Create ISO

