function Save-WebFile {
    <#
    .SYNOPSIS
        Downloads a file or fetches a URL with retry logic.

    .DESCRIPTION
        Wraps Invoke-WebRequest with a timeout and retries. 4xx responses
        fail immediately; transient failures retry up to MaxAttempts.
        Returns the saved file path when a DownloadDirectory is given,
        otherwise returns the web response.

    .EXAMPLE
        Save-WebFile -Uri $Url -DownloadDirectory "C:\Temp"
    #>
    param (
        [Parameter(Mandatory)]
        [uri]$Uri,
        [hashtable]$Headers,
        [string]$DownloadDirectory,
        [int]$TimeoutSec = 300,
        [int]$MaxAttempts = 5
    )

    $FileName = [uri]::UnescapeDataString([System.IO.Path]::GetFileName($Uri.AbsolutePath))

    $IWRParams = @{
        Uri             = $Uri
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
        ErrorAction     = "Stop"
    }

    if ($Headers) { $IWRParams.Headers = $Headers }

    if ($DownloadDirectory) {
        New-Folder -Path $DownloadDirectory | Out-Null

        $FilePath = Join-Path $DownloadDirectory $FileName
        $IWRParams.OutFile = $FilePath
    }

    # Download file
    for ($DownloadAttempt = 1; $DownloadAttempt -le $MaxAttempts; $DownloadAttempt++) {
        try {
            $Response = & {
                $ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest @IWRParams
            }

            if ($DownloadDirectory) { return $FilePath }

            return $Response
        }
        catch {
            # Try to pull the HTTP status code off the response, if there was one
            $StatusCode = $null
            if ($_.Exception.Response) {
                $StatusCode = [int]$_.Exception.Response.StatusCode
            }

            # 4xx = client error (404, 403, 401, etc.), fail immediately
            if ($StatusCode -ge 400 -and $StatusCode -lt 500) {
                Show-Error "Failed to download $FileName from $Uri (HTTP $StatusCode)."
                return
            }

            # Everything else (timeouts, 5xx, DNS failures, connection resets), retry
            if ($DownloadAttempt -ge $MaxAttempts) {
                Show-Error "Failed to download $FileName from $Uri after $MaxAttempts attempts."
                return
            }

            Start-Sleep -Seconds 1
        }
    }
}

function Save-GitHubFile {
    <#
    .SYNOPSIS
        Downloads one or more files from the Windots GitHub repo.

    .DESCRIPTION
        Downloads files from GitHub repo to the given directory via
        Save-WebFile.

    .EXAMPLE
        Save-GitHubFile -Files "windots/example.txt" -DownloadDirectory "C:\Temp"
    #>
    param (
        # Can pass an array to download multiple files at once
        [Parameter(Mandatory)]
        [string[]]$Files,

        # Specify the folder where the files will be downloaded
        [Parameter(Mandatory)]
        [string]$DownloadDirectory
    )

    $User    = "taylorstools"
    $Repo    = "windots"
    $Branch  = "main"

    foreach ($File in $Files) {
        # Build raw GitHub URL
        $DownloadUrl = "https://raw.githubusercontent.com/$User/$Repo/$Branch/$File"

        # Download the file(s)
        Save-WebFile -Uri $DownloadUrl -DownloadDirectory $DownloadDirectory -TimeoutSec 30
    }
}

function Confirm-Admin {
    <#
    .SYNOPSIS
        Ensures the session is running as administrator.

    .DESCRIPTION
        Checks whether the current identity is in the Administrator role
        and, if not, shows an error and exits with code 1.

    .EXAMPLE
        Confirm-Admin
    #>
    $IsAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $IsAdmin) {
        Show-Error "Not running as admin. Relaunch this script as an administrator."
        exit 1
    }
}

function Get-FilePicker {
    <#
    .SYNOPSIS
        Opens a Windows file-open dialog and returns the selected path(s).

    .DESCRIPTION
        Shows a WinForms OpenFileDialog using the given directory, filter,
        and title. Returns the selected file path, an array of paths when
        -Multiselect is used, or $null if the dialog is cancelled.

    .EXAMPLE
        Get-FilePicker -Filter "ISO Files (*.iso)|*.iso"
    #>
    [CmdletBinding()]
    param(
        [string]$Directory = "$env:USERPROFILE\Downloads",
        [string]$Filter    = "All Files (*.*)|*.*",
        [string]$Title     = "Select a file",
        [switch]$Multiselect
    )

    Add-Type -AssemblyName System.Windows.Forms

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = $Directory
        Filter           = $Filter
        Title            = $Title
        Multiselect      = $Multiselect.IsPresent
    }

    if ($OpenFileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    if ($Multiselect.IsPresent) {
        return $OpenFileDialog.FileNames
    }
    return $OpenFileDialog.FileName
}

function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a yes/no answer and returns a boolean.

    .DESCRIPTION
        Repeatedly prompts until a valid y/yes/n/no response is given and
        returns $true or $false. An optional default (Yes or No) is applied
        when the user presses Enter with no input.

    .EXAMPLE
        if (Read-YesNo "Continue?" -Default Yes) { }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [ValidateSet("Yes", "No", "None")]
        [string]$Default = "None"
    )

    $Suffix = switch ($Default) {
        "Yes"  { " [Y/n]" }
        "No"   { " [y/N]" }
        "None" { " [y/n]" }
    }

    while ($true) {
        $Response = (Read-Host -Prompt ("`n" + $Prompt + $Suffix)).Trim().ToLowerInvariant()

        if ([string]::IsNullOrEmpty($Response)) {
            if ($Default -eq "Yes") { return $true }
            if ($Default -eq "No")  { return $false }

            Write-Host "Please answer Y or N." -ForegroundColor Yellow
            continue
        }

        if ($Response -in @("y", "yes")) { return $true }
        if ($Response -in @("n", "no"))  { return $false }

        Write-Host "Invalid response `"$Response`". Please answer Y or N." -ForegroundColor Yellow
    }
}

function Write-Heading {
    <#
    .SYNOPSIS
        Writes a message inside a rounded Unicode box border.

    .DESCRIPTION
        Renders one or more lines of text inside a rounded border sized to
        the longest line, with configurable text color, border color, and
        inner padding. Bold is applied only when the host supports virtual
        terminal sequences.

    .EXAMPLE
        Write-Heading "Starting Phase 1" -BorderColor Cyan
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$Message,

        [Parameter()]
        [ConsoleColor]$TextColor = [ConsoleColor]::White,

        [Parameter()]
        [ConsoleColor]$BorderColor = [ConsoleColor]::Gray,

        [Parameter()]
        [int]$Padding = 2
    )

    # Legacy conhost on 5.1 has no VT processing, so bold codes would print literally
    $SupportsVT = $false
    try {
        $SupportsVT = [bool]$Host.UI.SupportsVirtualTerminal
    }
    catch {
        $SupportsVT = $false
    }

    $ESC     = [char]27
    $BoldOn  = if ($SupportsVT) { "$ESC[1m" } else { "" }
    $BoldOff = if ($SupportsVT) { "$ESC[0m" } else { "" }

    # Flatten any embedded newlines into individual lines
    $Lines = $Message -split "`r?`n"

    # Size the box to the longest line
    $MaxLength = ($Lines | Measure-Object -Property Length -Maximum).Maximum
    $Width = $MaxLength + ($Padding * 2)

    $TopBorder    = "╭" + ("─" * $Width) + "╮"
    $BottomBorder = "╰" + ("─" * $Width) + "╯"

    Write-Host ""
    Write-Host "$BoldOn$TopBorder$BoldOff" -ForegroundColor $BorderColor
    foreach ($Line in $Lines) {
        $RightPad  = $MaxLength - $Line.Length
        $InnerText = (" " * $Padding) + $Line + (" " * $RightPad) + (" " * $Padding)

        Write-Host "$BoldOn│$BoldOff"          -ForegroundColor $BorderColor -NoNewline
        Write-Host "$BoldOn$InnerText$BoldOff" -ForegroundColor $TextColor   -NoNewline
        Write-Host "$BoldOn│$BoldOff"          -ForegroundColor $BorderColor
    }
    Write-Host "$BoldOn$BottomBorder$BoldOff" -ForegroundColor $BorderColor
}

function Write-Section {
    <#
    .SYNOPSIS
        Writes a message preceded by a blank line.

    .DESCRIPTION
        Emits a leading blank line then the message, to visually separate
        sections of console output. Supports optional foreground and
        background colors.

    .EXAMPLE
        Write-Section "Downloading drivers..."
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [System.ConsoleColor]$TextColor = [System.ConsoleColor]::Gray,
        [System.ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )
    $Params = @{ ForegroundColor = $TextColor }
    if ($PSBoundParameters.ContainsKey("BackgroundColor")) {
        $Params.BackgroundColor = $BackgroundColor
    }
    if ($NoNewline) {
        $Params.NoNewline = $true
    }

    Write-Host ""
    Write-Host @Params "$Message"
}

function Write-Step {
    <#
    .SYNOPSIS
        Writes a single line of colored console text.

    .DESCRIPTION
        A thin Write-Host wrapper for emitting an individual step message
        with optional foreground and background colors.

    .EXAMPLE
        Write-Step "Copied install.wim" -TextColor Green
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [System.ConsoleColor]$TextColor = [System.ConsoleColor]::Gray,
        [System.ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )
    $Params = @{ ForegroundColor = $TextColor }
    if ($PSBoundParameters.ContainsKey("BackgroundColor")) {
        $Params.BackgroundColor = $BackgroundColor
    }
    if ($NoNewline) {
        $Params.NoNewline = $true
    }

    Write-Host @Params "$Message"
}

function New-Folder {
    <#
    .SYNOPSIS
        Creates a folder if it does not already exist.

    .DESCRIPTION
        Returns the full path of the directory, creating it (including any
        missing parents) when it is not already present. Throws on failure
        so callers never receive an empty path.

    .EXAMPLE
        New-Folder -Path "C:\WinDots"
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $Folder = if (Test-Path -LiteralPath $Path -PathType Container) {
            Get-Item -LiteralPath $Path
        }
        else {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
        }

        $Folder.FullName
    }
    catch {
        throw "Failed to create folder ${Path}: $($_.Exception.Message)"
    }
}

function Show-Error {
    <#
    .SYNOPSIS
        Writes a formatted error message to the console.

    .DESCRIPTION
        Prints the message in red with an error glyph and, when an
        ErrorRecord is supplied, an additional DETAILS line containing the
        exception message.

    .EXAMPLE
        Show-Error "Download failed." -ErrorRecord $_
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    Write-Host "`n$([char]0x274C) ERROR! $Message" -ForegroundColor Red

    if ($ErrorRecord -and $ErrorRecord.Exception) {
        Write-Host "$([char]0x274C) DETAILS: $($ErrorRecord.Exception.Message)" -ForegroundColor Red
    }
}

function Remove-Path {
    <#
    .SYNOPSIS
        Deletes a path (recursively) if it exists.

    .DESCRIPTION
        Accepts one or more paths, including from the pipeline, and
        recursively and forcefully removes each one that exists. Missing
        paths are silently skipped.

    .EXAMPLE
        "C:\Temp\old" | Remove-Path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("FullName", "PSPath")]
        [string[]]$Path
    )

    process {
        foreach ($Item in $Path) {
            if (Test-Path -LiteralPath $Item) {
                Remove-Item -LiteralPath $Item -Recurse -Force -ErrorAction Stop
            }
        }
    }
}

function Set-RegValue {
    <#
    .SYNOPSIS
        Creates a registry key and optionally sets a value on it.

    .DESCRIPTION
        Ensures the key path exists, creating any missing parent keys, and
        when a Name, Value, and Type are supplied, creates or overwrites
        that value.

    .EXAMPLE
        Set-RegValue -Path "HKLM:\SOFTWARE\Test" -Name "Test" -Value 1 -Type DWord
    #>
    [CmdletBinding(DefaultParameterSetName = "KeyOnly")]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = "Value")]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = "Value")]
        [object]$Value,

        [Parameter(Mandatory, ParameterSetName = "Value")]
        [ValidateSet("String", "ExpandString", "Binary", "DWord", "MultiString", "QWord")]
        [string]$Type
    )

    # New-Item with -Force creates every missing parent key in the path.
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    # Only touch a value when we're in the 'Value' parameter set.
    if ($PSCmdlet.ParameterSetName -eq "Value") {
        New-ItemProperty -Path $Path -Name $Name -Value $Value `
            -PropertyType $Type -Force | Out-Null
    }
}

function Remove-RegValue {
    <#
    .SYNOPSIS
        Removes a registry value, or an entire key when no name is given.

    .DESCRIPTION
        When -Name is supplied, removes just that value if it exists;
        otherwise removes the whole key recursively.

    .EXAMPLE
        Remove-RegValue -Path "HKLM:\SOFTWARE\Test" -Name "Test"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        return
    }

    if ($PSBoundParameters.ContainsKey("Name")) {
        # -Name was passed: remove just that value.
        $Exists = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($Exists) {
            Remove-ItemProperty -Path $Path -Name $Name -Force
        }
    }
    else {
        # No -Name: remove the entire key and everything under it.
        Remove-Item -Path $Path -Recurse -Force
    }
}

function Remove-SystemDrivePath {
    <#
    .SYNOPSIS
        Removes non-essential top-level folders from a Windows drive root.

    .DESCRIPTION
        Deletes every visible top-level directory on the given drive except
        a whitelist of protected folders (Windows, Users, Program Files,
        etc.), leaving hidden folders untouched. Drive is mandatory so this
        can never silently target the live system drive.

    .EXAMPLE
        Remove-SystemDrivePath -Drive "C:\ScratchDir\Workspace"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Drive,

        [string[]]$KeepFolder = @(
            "Program Files",
            "Program Files (Arm)",
            "Program Files (x86)",
            "ProgramData",
            "Users",
            "Windows"
        )
    )

    $Root = Join-Path -Path $Drive -ChildPath "\"

    Get-ChildItem -Path $Root -Directory |
        Where-Object {
            -not $_.Attributes.HasFlag([System.IO.FileAttributes]::Hidden) -and
            $_.Name -notin $KeepFolder
        } |
        Remove-Path
}