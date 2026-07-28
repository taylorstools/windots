<#
.SYNOPSIS
    Creates a new WinDots Windows 11 ISO file.

.DESCRIPTION
    Asks user to select their NTLite Windows 11 ISO. From there, performs modifications
    to the image to convert it to a WinDots ISO. Once complete, exports a new ISO to
    user's Desktop.

.EXAMPLE
    Script is meant to be called like:

    iwr -useb https://raw.githubusercontent.com/taylorstools/windots/main/New-ISO.ps1 |
        iex

.NOTES
    Author      : taylorstools
    Created     : 2025-11-11
    Last Updated: 2026-07-27
#>

$ErrorActionPreference = "Stop"

#region Import WinDots Module

function Import-GitHubModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$Files
    )

    $BaseUrl = "https://raw.githubusercontent.com/taylorstools/windots/main"

    foreach ($File in $Files) {
        $ModuleName = [System.IO.Path]::GetFileNameWithoutExtension($File)
        $Uri        = "$BaseUrl/$File"

        try {
            $Content = (Invoke-WebRequest -Uri $Uri `
                                          -UseBasicParsing).Content
        }
        catch {
            throw "Failed to download ${File}: $($_.Exception.Message)"
        }

        New-Module -Name $ModuleName -ScriptBlock ([ScriptBlock]::Create($Content)) |
            Import-Module -Force -Global
    }
}

Import-GitHubModule -Files @("WinDots.psm1")

#endregion Import WinDots Module

#region Requirements

Clear-Host
$Host.UI.RawUI.WindowTitle = "WinDots ISO Creation"
Write-Heading "WinDots ISO Creation"

Write-Section "Checking requirements..."

# Check running as admin
Confirm-Admin

$SevenZipPath = $null
$SevenZipCandidates = @(
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
)

foreach ($Path in $SevenZipCandidates) {
    if (Test-Path -Path $Path -PathType Leaf) {
        $SevenZipPath = $Path
        break
    }
}

# Extracted ISO + exported wim + mounted image + output ISO all live on the system drive
$RequiredFreeGB = 30
$FreeGB = [math]::Round(
    (Get-PSDrive -Name $env:SystemDrive.TrimEnd(":")).Free / 1GB, 1
)

$Requirements = @(
    @{
        Name   = "7-Zip"
        Met    = [bool]$SevenZipPath
        Detail = "Install 7-Zip from https://www.7-zip.org and re-run."
    },
    @{
        Name   = "Free disk space on $env:SystemDrive\"
        Met    = $FreeGB -ge $RequiredFreeGB
        Detail = "Need roughly $RequiredFreeGB GB; only $FreeGB GB available."
    }
)

$Missing = $Requirements | Where-Object { -not $_.Met }

if ($Missing) {
    Show-Error "Your PC does not meet the requirements to build a WinDots ISO:"
    $Missing | ForEach-Object {
        Write-Step "- $($_.Name): $($_.Detail)"
    }

    exit 1
}

#endregion Requirements

#region User Input

Write-Section "Select your NTLite Windows 11 .ISO file..." -TextColor Black -BackgroundColor Yellow
Start-Sleep 2

$WindowsISO = $null
do {
    $WindowsISO = Get-FilePicker -Filter "ISO Files (*.iso)|*.iso"

    if ($WindowsISO) {
        Write-Step "Selected Windows 11 ISO file: $WindowsISO"
    }
    else {
        $ISOProceed = Read-YesNo -Prompt "No file selected. Do you want to try again?" -Default "Yes"

        if (-not $ISOProceed) {
            Show-Error "No Windows 11 ISO file selected."
            exit 1
        }
    }
} while (-not $WindowsISO)

#endregion User Input

#region Workspace Setup

Write-Section "Cleaning up any stale mounted images..."

Get-WindowsImage -Mounted |
    Where-Object { $_.Path -like "$env:SystemDrive\ScratchDir-*" } |
    ForEach-Object {
        Write-Step "Discarding stale mount at $($_.Path)..." -TextColor Yellow
        Dismount-WindowsImage -Path $_.Path -Discard -ErrorAction SilentlyContinue
    }

Clear-WindowsCorruptMountPoint | Out-Null

# Remove leftover scratch directories from previous failed runs
Get-ChildItem -Path "$env:SystemDrive\" -Directory -Filter "ScratchDir-*" `
    -ErrorAction SilentlyContinue |
        ForEach-Object {
            $StalePath = $_.FullName

            try {
                Remove-Path -Path $StalePath
            }
            catch {
                # Usually a file still locked by a previous run; not fatal, so warn and move on
                Write-Step "Could not remove stale scratch directory ${StalePath}: $($_.Exception.Message)" `
                    -TextColor Yellow
            }
        }

Write-Section "Creating scratch directories..."

$ScratchDir = "$env:SystemDrive\ScratchDir-$([Guid]::NewGuid())"
New-Folder -Path $ScratchDir | Out-Null

# Unique offline registry hive mount name
$OfflineHive = "OFFLINE-$([Guid]::NewGuid())"

# For extracted Windows .iso file
$ExtractedISO = New-Folder -Path "$ScratchDir\Extracted"

# For mounted Windows install.wim
$Workspace = New-Folder -Path "$ScratchDir\Workspace"

# For mounted Windows boot.wim
$BootWorkspace = New-Folder -Path "$ScratchDir\BootWorkspace"

Write-Section "Extracting Windows ISO to scratch directory..."

& {
    $ErrorActionPreference = "Continue"
    & $SevenZipPath x $WindowsISO "-o$ExtractedISO" -y 2>&1 | Out-Null
}

if ($LASTEXITCODE -ne 0) {
    Show-Error "7-Zip failed to extract the ISO (exit code $LASTEXITCODE)."
    exit 1
}

#endregion Workspace Setup

#region Check Install.wim Indexes

if (Test-Path -Path "$ExtractedISO\sources\install.wim") {
    $Wim = "install.wim"
}
elseif (Test-Path -Path "$ExtractedISO\sources\install.esd") {
    $Wim = "install.esd"
}
else {
    Show-Error "No install.wim or install.esd found in `"sources`" folder in extracted ISO."
    exit 1
}

$ImagePath = "$ExtractedISO\sources\$Wim"
$Images = @(Get-WindowsImage -ImagePath $ImagePath)

$Index = $Images |
    Where-Object { $_.ImageName -eq "Windows 11 IOT Enterprise LTSC" } |
    Select-Object -ExpandProperty ImageIndex -First 1

if (-not $Index) {
    Show-Error "Windows 11 ISO does not contain an IOT Enterprise LTSC Edition index."
    exit 1
}

# ESDs cannot be mounted
if ($Images.Count -gt 1 -or $Wim -eq "install.esd") {
    Write-Section "Exporting IOT Enterprise LTSC index to a mountable install.wim..."

    $TempPath = "$ExtractedISO\sources\export.wim"
    $NewPath  = "$ExtractedISO\sources\install.wim"

    try {
        Remove-Path -Path $TempPath

        Export-WindowsImage -SourceImagePath $ImagePath `
                            -SourceIndex $Index `
                            -DestinationImagePath $TempPath `
                            -CompressionType Max `
                            -CheckIntegrity

        Remove-Path -Path $ImagePath
        Move-Item -Path $TempPath -Destination $NewPath -Force

        $ImagePath = $NewPath
    }
    catch {
        Show-Error "Failed to export IOT Enterprise LTSC edition: $($_.Exception.Message)"
        exit 1
    }
}

# Get build info for naming resulting ISO
$OS = Get-WindowsImage -ImagePath $ImagePath -Index 1
$OSBuild = "$($OS.ImageName) $($OS.Version)"

#endregion Check Install.wim Indexes

#region Mount Install.wim and Make Changes

Write-Section "Mounting the Windows wim..."
Mount-WindowsImage -ImagePath $ImagePath -Index 1 -Path $Workspace

# Track commit state so the finally block only discards a still-mounted image
$InstallCommitted = $false
$InstallError     = $null

try {
    Write-Section "Applying default app associations..."

    # Copy default apps XML
    $AppAssociationsXml = Save-GitHubFile -Files @("iso/AppAssociations.xml") `
        -DownloadDirectory $ScratchDir

    if (-not $AppAssociationsXml) {
        throw "Failed to download AppAssociations.xml."
    }

    # Import default apps XML
    & dism.exe "/Image:$Workspace" "/Import-DefaultAppAssociations:$AppAssociationsXml"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to import default app associations (exit code $LASTEXITCODE)."
    }

    # Change UAC prompt behavior
    Write-Section "Changing UAC consent prompt behavior..."
    reg load "HKLM\$OfflineHive" "$Workspace\Windows\System32\Config\SOFTWARE" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to load offline SOFTWARE hive (exit code $LASTEXITCODE)."
    }

    try {
        Set-RegValue -Path "HKLM:\$OfflineHive\Microsoft\Windows\CurrentVersion\Policies\System" `
            -Name "ConsentPromptBehaviorAdmin" -Value 0 -Type DWord
    }
    finally {
        # A lingering handle keeps the hive mounted, which then blocks the dismount,
        # so collect and retry rather than trusting a single unload
        for ($UnloadAttempt = 1; $UnloadAttempt -le 3; $UnloadAttempt++) {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
            reg unload "HKLM\$OfflineHive" | Out-Null

            if ($LASTEXITCODE -eq 0) { break }

            Start-Sleep -Seconds 2
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to unload offline hive HKLM\$OfflineHive (exit code $LASTEXITCODE)."
        }
    }

    Write-Section "Cleaning up miscellaneous C:\ folders on wim..."
    Remove-SystemDrivePath -Drive $Workspace

    Write-Section "Saving changes and unmounting Windows wim..."
    Dismount-WindowsImage -Path $Workspace -Save
    $InstallCommitted = $true
}
catch {
    $InstallError = $_
}
finally {
    if (-not $InstallCommitted) {
        Write-Step "Discarding changes and unmounting install.wim..." -TextColor Yellow
        Dismount-WindowsImage -Path $Workspace -Discard -ErrorAction SilentlyContinue
    }
}

if ($InstallError) {
    Show-Error "Failed while modifying install.wim." -ErrorRecord $InstallError
    exit 1
}

Remove-Path $Workspace

#endregion Mount Install.wim and Make Changes

#region Check Boot.wim Indexes

$BootPath = "$ExtractedISO\sources\boot.wim"

if (-not (Test-Path -Path $BootPath -PathType Leaf)) {
    Show-Error "No boot.wim found in `"sources`" folder in extracted ISO."
    exit 1
}

$BootImages = @(Get-WindowsImage -ImagePath $BootPath)

$BootIndex = $BootImages |
    Where-Object { $_.ImageName -like "*Microsoft Windows Setup*" } |
    Select-Object -ExpandProperty ImageIndex -First 1

if (-not $BootIndex) {
    Show-Error "Windows ISO boot.wim does not contain a Windows Setup index."
    exit 1
}

# Trim the WinPE index so only the bootable Setup index remains
if ($BootImages.Count -gt 1) {
    Write-Section "Exporting the Windows Setup index to a new boot.wim..."

    $BootTempPath = "$ExtractedISO\sources\bootexport.wim"

    try {
        Remove-Path -Path $BootTempPath

        Export-WindowsImage -SourceImagePath $BootPath `
                            -SourceIndex $BootIndex `
                            -DestinationImagePath $BootTempPath `
                            -CompressionType Max `
                            -CheckIntegrity `
                            -SetBootable

        Remove-Path -Path $BootPath
        Move-Item -Path $BootTempPath -Destination $BootPath -Force
    }
    catch {
        Show-Error "Failed to export the Windows Setup index: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Check Boot.wim Indexes

#region Mount Boot.wim and Make Changes

Write-Section "Mounting boot.wim..."
Mount-WindowsImage -ImagePath $BootPath -Index 1 -Path $BootWorkspace

$BootCommitted = $false
$BootError     = $null

try {
    Write-Section "Renaming setup.exe within boot.wim..."

    $SetupExe = "$BootWorkspace\setup.exe"

    if (-not (Test-Path -LiteralPath $SetupExe -PathType Leaf)) {
        throw "boot.wim does not contain setup.exe at its root. Is this a Windows Setup image?"
    }

    Rename-Item -Path $SetupExe -NewName "setup-windots.exe"

    Write-Section "Downloading startnet.cmd script from repo to boot.wim..."
    Remove-Path "$BootWorkspace\Windows\System32\startnet.cmd"

    $StartNet = Save-GitHubFile -Files @("iso/startnet.cmd") `
        -DownloadDirectory "$BootWorkspace\Windows\System32"

    if (-not $StartNet) {
        throw "Failed to download startnet.cmd."
    }

    Write-Section "Saving changes and unmounting modified boot.wim..."
    Dismount-WindowsImage -Path $BootWorkspace -Save
    $BootCommitted = $true
}
catch {
    $BootError = $_
}
finally {
    if (-not $BootCommitted) {
        Write-Step "Discarding changes and unmounting boot.wim..." -TextColor Yellow
        Dismount-WindowsImage -Path $BootWorkspace -Discard -ErrorAction SilentlyContinue
    }
}

if ($BootError) {
    Show-Error "Failed while modifying boot.wim." -ErrorRecord $BootError
    exit 1
}

Remove-Path $BootWorkspace

#endregion Mount Boot.wim and Make Changes

#region Make ISO Changes

$AutounattendXml = Save-GitHubFile -Files @("iso/autounattend.xml") `
    -DownloadDirectory $ExtractedISO

if (-not $AutounattendXml) {
    Show-Error "Failed to download autounattend.xml into extracted ISO."
    exit 1
}

#endregion Make ISO Changes

#region Create ISO

$Oscdimg = Save-GitHubFile -Files @("iso/oscdimg.exe") -DownloadDirectory $ScratchDir

if (-not $Oscdimg) {
    Show-Error "Failed to download oscdimg.exe from GitHub repo."
    exit 1
}

$OutputDirectory = [Environment]::GetFolderPath("Desktop")
if (-not $OutputDirectory) {
    $OutputDirectory = "$env:USERPROFILE\Desktop"
}

$Date = Get-Date -Format "MM-dd-yy"

# ImageName comes from the wim metadata, so strip anything illegal in a file name
$InvalidChars = [RegEx]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
$IsoName = "WinDots $OSBuild $Date" -replace "[$InvalidChars]", "-"

$IsoPath = Join-Path $OutputDirectory "$IsoName.iso"
$Counter = 2

# Construct a different ISO path if file already exists
while (Test-Path -LiteralPath $IsoPath) {
    $IsoPath = Join-Path $OutputDirectory "$IsoName $Counter.iso"
    $Counter++
}

$BootFiles = @(
    "$ExtractedISO\boot\etfsboot.com",
    "$ExtractedISO\efi\microsoft\boot\efisys.bin"
)

$MissingBootFiles = $BootFiles | Where-Object { -not (Test-Path -Path $_ -PathType Leaf) }

if ($MissingBootFiles) {
    Show-Error "The extracted ISO is missing required boot files:"
    $MissingBootFiles | ForEach-Object { Write-Step "- $_" }
    exit 1
}

$BootData = "2#p0,e,b$($BootFiles[0])#pEF,e,b$($BootFiles[1])"

Write-Section "Creating ISO..."
& $Oscdimg -m -o -u2 -udfver102 "-bootdata:$BootData" "$ExtractedISO" "$IsoPath"

if ($LASTEXITCODE -ne 0) {
    Show-Error "oscdimg failed with exit code $LASTEXITCODE."
    exit 1
}

Write-Section "WinDots ISO successfully created at path:"
Write-Step "$IsoPath"

Write-Section "Cleaning up..."
Remove-Path $ScratchDir

Write-Heading -TextColor Green -BorderColor Green "DONE"

#endregion Create ISO