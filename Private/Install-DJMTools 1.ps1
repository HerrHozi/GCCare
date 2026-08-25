#Requires -Version 7.0

<#
.SYNOPSIS
    Installs all tools required for the DJM training labs.

.DESCRIPTION
    Install-DJMTools prepares a fresh Windows machine for the DJM training lab
    environment. It disables Windows Defender real-time monitoring, adds path
    exclusions for common working folders, then installs each required tool in
    dependency order using winget, pip, PowerShell Gallery, or direct download
    as appropriate.

    Run as administrator. The script will terminate early if not elevated.

.EXAMPLE
    .\Install-DJMTools.ps1

    Runs the full installation sequence interactively.

.EXAMPLE
    .\Install-DJMTools.ps1 -LoadFunctionsOnly

    Dot-sources the script to load all functions into scope without executing
    the main installation block. Used by Pester tests.

.NOTES
    Version:    2026.4.231200
    Author:     Jake Hildreth
    Requires:   PowerShell 7.0+, Administrator privileges, internet access

    pip calls are routed through 'python -m pip' to guarantee the same Python
    installation is used regardless of PATH pip/pip3 naming differences.
#>





function Write-Status {
    <#
    .SYNOPSIS
        Writes colorized status output using semantic levels.

    .DESCRIPTION
        Central status writer for UI output. Maps message levels to
        foreground colors and prints a single line.

    .PARAMETER Level
        Semantic message level.

    .PARAMETER Message
        Text to display.

    .PARAMETER NoNewLine
        Writes without a trailing newline when specified.

    .EXAMPLE
        Write-Status -Level Info -Message '[i] Starting install'

    .OUTPUTS
        None

    .NOTES
        Used by the script-scoped Write-StatusByPrefix proxy for prefix-based coloring.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning', 'Success', 'Info', 'Step', 'Action', 'Skip', 'Header', 'Default')]
        [string]$Level,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [switch]$NoNewLine
    )

    $foregroundColor = switch ($Level) {
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        'Step' { 'Blue' }
        'Action' { 'Magenta' }
        'Skip' { 'DarkGray' }
        'Header' { 'White' }
        default { 'Gray' }
    }

    if ($NoNewLine) {
        Microsoft.PowerShell.Utility\Write-Host -Object $Message -ForegroundColor $foregroundColor -NoNewline
    }
    else {
        Microsoft.PowerShell.Utility\Write-Host -Object $Message -ForegroundColor $foregroundColor
    }
}

function Write-StatusByPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [object[]]$Object,

        [Parameter()]
        [switch]$NoNewline
    )

    $message = if ($null -eq $Object) { '' } else { ($Object | ForEach-Object { [string]$_ }) -join ' ' }
    $level = switch ($true) {
        ($message.StartsWith('[i]')) { 'Info'; break }
        ($message.StartsWith('[>]')) { 'Step'; break }
        ($message.StartsWith('[+]')) { 'Action'; break }
        ($message.StartsWith('[-]')) { 'Action'; break }
        ($message.StartsWith('[x]')) { 'Success'; break }
        default { 'Default' }
    }

    Write-Status -Level $level -Message $message -NoNewLine:$NoNewline
}

function Initialize-ScriptLogging {
    <#
    .SYNOPSIS
        Initializes per-run logging for this script.

    .DESCRIPTION
        Creates the log directory when needed and sets a timestamped log file
        path for the current execution.

    .PARAMETER ScriptTag
        Short tag used in the log file name.

    .EXAMPLE
        Initialize-ScriptLogging -ScriptTag 'install-djmtools'

    .OUTPUTS
        System.String. The full log file path.

    .NOTES
        Safe to call once per script execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptTag
    )

    if (-not (Test-Path -Path $script:LogDirectory)) {
        New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFilePath = Join-Path -Path $script:LogDirectory -ChildPath "$ScriptTag-$timestamp.log"
    New-Item -Path $script:LogFilePath -ItemType File -Force | Out-Null
    return $script:LogFilePath
}

function Write-LogEntry {
    <#
    .SYNOPSIS
        Appends a single timestamped entry to the current script log.

    .DESCRIPTION
        Writes a line to the active log file when logging is initialized.

    .PARAMETER Message
        Message text to write.

    .PARAMETER Level
        Log level label (INFO/WARN/ERROR/DEBUG).

    .EXAMPLE
        Write-LogEntry -Message 'Starting winget install' -Level 'INFO'

    .OUTPUTS
        None

    .NOTES
        No-op when logging is not initialized.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -Path $script:LogFilePath -Value "[$timestamp] [$Level] $Message"
}

function Get-SanitizedLogLine {
    <#
    .SYNOPSIS
        Normalizes one captured output line before it is appended to the log.

    .DESCRIPTION
        Removes ANSI/control noise and drops progress-only lines such as
        spinner frames and download bars while preserving meaningful text.

    .PARAMETER Line
        Raw line captured from an external command output file.

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    $sanitizedLine = $Line
    $sanitizedLine = [regex]::Replace($sanitizedLine, "`e\[[0-9;?]*[ -/]*[@-~]", '')
    $sanitizedLine = [regex]::Replace($sanitizedLine, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '')
    $sanitizedLine = $sanitizedLine.Trim()

    if ([string]::IsNullOrWhiteSpace($sanitizedLine)) {
        return $null
    }

    $progressOnlyPattern = '^[\s\d\.,:%/\\()\[\]\|\-+BKMGTPEZYbkmgtpezy█▉▊▋▌▍▎▏▒▓■□▪▫▄▀▐▌⠁-⣿]+$'
    if ($sanitizedLine -match $progressOnlyPattern) {
        return $null
    }

    return $sanitizedLine
}

function Add-LogFileContent {
    <#
    .SYNOPSIS
        Appends contents of a file into the current script log.

    .DESCRIPTION
        Adds section headers and raw file content to the active log file.

    .PARAMETER Header
        Section header for the appended content.

    .PARAMETER FilePath
        Source file path to append.

    .EXAMPLE
        Add-LogFileContent -Header 'winget output' -FilePath $captureFile

    .OUTPUTS
        None

    .NOTES
        No-op when logging is not initialized or source file is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Header,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) {
        return
    }
    if (-not (Test-Path -Path $FilePath)) {
        return
    }

    $rawContent = Get-Content -Path $FilePath -Raw

    Write-LogEntry -Message "----- BEGIN $Header -----"
    [regex]::Split($rawContent, "`r`n|`r|`n") | ForEach-Object {
        $sanitizedLine = Get-SanitizedLogLine -Line $_
        if (-not [string]::IsNullOrWhiteSpace($sanitizedLine)) {
            Add-Content -Path $script:LogFilePath -Value $sanitizedLine
        }
    }
    Write-LogEntry -Message "----- END $Header -----"
}

function Confirm-InstalledState {
    <#
    .SYNOPSIS
        Re-runs an install check and reports the result.

    .DESCRIPTION
        Executes the provided Test-*Installed script block after an install
        attempt so the script can confirm the tool is actually available.

    .PARAMETER ToolName
        Friendly name of the tool being verified.

    .PARAMETER TestScript
        Script block that returns $true when the tool is installed.

    .EXAMPLE
        Confirm-InstalledState -ToolName 'Python' -TestScript { Test-PythonInstalled }

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock]$TestScript
    )

    $isInstalled = & $TestScript
    if ($isInstalled) {
        Write-StatusByPrefix "[x] Confirmed installed: $ToolName"
        Write-LogEntry -Message "Confirmed installed: $ToolName"
        return $true
    }

    Write-Warning -Message "Install completed but verification failed for $ToolName."
    Write-LogEntry -Message "Verification failed for $ToolName" -Level 'WARN'
    return $false
}

#region Private Helpers

function Invoke-WingetInstall {
    <#
    .SYNOPSIS
        Installs a package via winget and returns the exit code.

    .DESCRIPTION
        Wraps winget install with standard flags for non-interactive, silent
        installation. Accepts package agreements automatically.

    .PARAMETER PackageId
        The winget package identifier (e.g., 'Mozilla.Firefox').

    .PARAMETER Scope
        Installation scope. Defaults to 'user'. Use 'machine' for system-wide
        installs (requires admin).

    .EXAMPLE
        Invoke-WingetInstall -PackageId 'Mozilla.Firefox'

    .EXAMPLE
        Invoke-WingetInstall -PackageId 'Microsoft.AzureCLI' -Scope 'machine'

    .OUTPUTS
        System.Int32. The winget process exit code. 0 indicates success.

    .NOTES
        Caller is responsible for checking the return value. All installs are
        pinned to --source winget to avoid certificate failures on the msstore
        source.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter()]
        [ValidateSet('user', 'machine')]
        [string]$Scope = 'user'
    )

    $wingetArgs = @(
        'install'
        '--id', $PackageId
        '--source', 'winget'
        '--scope', $Scope
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
        '--silent'
    )

    $captureFile = Join-Path -Path $env:TEMP -ChildPath ("djm-winget-install-{0}.log" -f [Guid]::NewGuid())
    try {
        & winget @wingetArgs *> $captureFile
        $exitCode = $LASTEXITCODE
        Add-LogFileContent -Header "winget install $PackageId (scope=$Scope, exit=$exitCode)" -FilePath $captureFile
        return $exitCode
    }
    finally {
        Remove-Item -Path $captureFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PipInstall {
    <#
    .SYNOPSIS
        Installs a Python package via pip and returns the exit code.

    .DESCRIPTION
        Wraps pip install with --user flag for user-scoped installation.

    .PARAMETER PackageName
        The PyPI package name (e.g., 'roadrecon').

    .EXAMPLE
        Invoke-PipInstall -PackageName 'roadrecon'

    .OUTPUTS
        System.Int32. The pip process exit code. 0 indicates success.

    .NOTES
        Requires Python to already be installed and on PATH.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName
    )

    $captureFile = Join-Path -Path $env:TEMP -ChildPath ("djm-pip-install-{0}.log" -f [Guid]::NewGuid())
    try {
        python -m pip install --user $PackageName *> $captureFile
        $exitCode = $LASTEXITCODE
        Add-LogFileContent -Header "pip install $PackageName (exit=$exitCode)" -FilePath $captureFile
        return $exitCode
    }
    finally {
        Remove-Item -Path $captureFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PipRequirementsInstall {
    <#
    .SYNOPSIS
        Installs Python requirements from a requirements.txt file.

    .DESCRIPTION
        Wraps `python -m pip install --user --no-cache-dir -r` and captures all
        output into the script log instead of streaming it to the host.

    .PARAMETER RequirementsFile
        Full path to the requirements.txt file.

    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RequirementsFile
    )

    $captureFile = Join-Path -Path $env:TEMP -ChildPath ("djm-pip-requirements-{0}.log" -f [Guid]::NewGuid())
    try {
        python -m pip install --user --no-cache-dir -r $RequirementsFile *> $captureFile
        $exitCode = $LASTEXITCODE
        Add-LogFileContent -Header "pip install requirements $RequirementsFile (exit=$exitCode)" -FilePath $captureFile
        return $exitCode
    }
    finally {
        Remove-Item -Path $captureFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-GitClone {
    <#
    .SYNOPSIS
        Clones a git repository with output captured to the script log.

    .DESCRIPTION
        Wraps `git clone` so progress and transfer output do not clutter the
        host while preserving raw output in the run log.

    .PARAMETER RepositoryUrl
        Repository URL to clone.

    .PARAMETER DestinationPath
        Destination folder for the clone.

    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath
    )

    $captureFile = Join-Path -Path $env:TEMP -ChildPath ("djm-git-clone-{0}.log" -f [Guid]::NewGuid())
    try {
        git clone $RepositoryUrl $DestinationPath *> $captureFile
        $exitCode = $LASTEXITCODE
        Add-LogFileContent -Header "git clone $RepositoryUrl -> $DestinationPath (exit=$exitCode)" -FilePath $captureFile
        return $exitCode
    }
    finally {
        Remove-Item -Path $captureFile -Force -ErrorAction SilentlyContinue
    }
}

function Add-UserPathEntryIfMissing {
    <#
    .SYNOPSIS
        Adds a directory to the User PATH if it is not already present.

    .DESCRIPTION
        Reads the current User PATH, appends the provided directory when
        missing, writes the updated User PATH back to the registry, and updates
        the current process PATH so the change is immediately available.

    .PARAMETER PathEntry
        The directory path to add to the User PATH.

    .EXAMPLE
        Add-UserPathEntryIfMissing -PathEntry 'C:\Users\User\AppData\Roaming\Python\Python313\Scripts'

    .OUTPUTS
        System.Boolean. Returns $true when the entry exists or was added;
        otherwise $false.

    .NOTES
        User PATH updates affect new shells automatically and the current
        process immediately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PathEntry
    )

    if (-not (Test-Path -Path $PathEntry)) {
        return $false
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrWhiteSpace($currentUserPath)) {
        $currentUserPath = ''
    }

    $pathEntries = $currentUserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($pathEntries -contains $PathEntry) {
        return $true
    }

    $updatedUserPath = if ([string]::IsNullOrWhiteSpace($currentUserPath)) {
        $PathEntry
    }
    else {
        "$currentUserPath;$PathEntry"
    }

    [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    return $true
}

function New-ToolShortcut {
    <#
    .SYNOPSIS
        Creates a Windows .lnk shortcut in the specified folder.

    .DESCRIPTION
        Uses the WScript.Shell COM object to create a .lnk shortcut pointing to
        the specified target executable. Returns $true on success, $false if the
        target path does not exist.

    .PARAMETER TargetPath
        Full path to the executable the shortcut should point to.

    .PARAMETER ShortcutName
        Display name for the shortcut, without the .lnk extension.

    .PARAMETER DestinationFolder
        Folder in which to create the shortcut file.

    .EXAMPLE
        New-ToolShortcut -TargetPath 'C:\Program Files\Mozilla Firefox\firefox.exe' -ShortcutName 'Firefox' -DestinationFolder 'C:\Users\User\Desktop\DJMTools'

    .OUTPUTS
        System.Boolean. Returns $true if the shortcut was created, $false if the target was not found.

    .NOTES
        Skips with a warning if the target executable does not exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ShortcutName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationFolder
    )

    if (-not (Test-Path -Path $TargetPath)) {
        Write-Warning -Message "Shortcut target not found, skipping: $TargetPath"
        return $false
    }

    $shortcutPath = Join-Path -Path $DestinationFolder -ChildPath "$ShortcutName.lnk"
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Save()
    return $true
}

function Invoke-FirefoxSilentUninstall {
    <#
    .SYNOPSIS
        Runs Firefox native silent uninstall using helper.exe.

    .DESCRIPTION
        Locates Firefox uninstall helper executable in known install paths and
        invokes it with /S. Returns helper exit code when executed, or $null if
        helper.exe is not found.

    .EXAMPLE
        Invoke-FirefoxSilentUninstall

    .OUTPUTS
        System.Nullable[System.Int32]

    .NOTES
        This avoids interactive vendor UI that may still appear with winget
        uninstall on older winget versions.
    #>
    [CmdletBinding()]
    param()

    $helperPaths = @(
        (Join-Path -Path ${env:ProgramFiles} -ChildPath 'Mozilla Firefox\uninstall\helper.exe'),
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Mozilla Firefox\uninstall\helper.exe'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Mozilla Firefox\uninstall\helper.exe')
    )

    $helperPath = $helperPaths | Where-Object { Test-Path -Path $_ } | Select-Object -First 1
    if (-not $helperPath) {
        return $null
    }

    $process = Start-Process -FilePath $helperPath -ArgumentList '/S' -Wait -PassThru -NoNewWindow
    return $process.ExitCode
}

#endregion

#region Test-*Installed Functions

function Test-PythonInstalled {
    <#
    .SYNOPSIS
        Tests whether a real Python installation is available on PATH.

    .DESCRIPTION
        Uses Get-Command to locate the 'python' executable, then verifies it is
        not the Windows Store app execution alias stub located in the
        WindowsApps folder. The stub redirects to the Microsoft Store and is
        not a functional Python installation.

    .EXAMPLE
        Test-PythonInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        The Windows Store alias lives in:
        $env:LOCALAPPDATA\Microsoft\WindowsApps\python.exe
    #>
    [CmdletBinding()]
    param()

    $pythonCmd = Get-Command -Name 'python' -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        return $false
    }
    # Exclude the Windows Store app execution alias stub
    if ($pythonCmd.Source -like '*WindowsApps*') {
        return $false
    }
    return $true
}

function Test-GitInstalled {
    <#
    .SYNOPSIS
        Tests whether Git is installed and available on PATH.

    .DESCRIPTION
        Uses Get-Command to check for the 'git' executable on the current PATH.
        Returns $true if found, $false otherwise.

    .EXAMPLE
        Test-GitInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param()

    return [bool](Get-Command -Name 'git' -ErrorAction SilentlyContinue)
}

function Test-RoadreconInstalled {
    <#
    .SYNOPSIS
        Tests whether roadrecon is installed as a Python package.

    .DESCRIPTION
        Uses python -m pip show to check if roadrecon is installed. This is
        more reliable than Get-Command because pip --user scripts may not be
        on PATH in all sessions.

    .EXAMPLE
        Test-RoadreconInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        roadrecon is installed via pip install --user roadrecon.
    #>
    [CmdletBinding()]
    param()

    python -m pip show roadrecon 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-RoadtxInstalled {
    <#
    .SYNOPSIS
        Tests whether roadtx is installed as a Python package.

    .DESCRIPTION
        Uses python -m pip show to check if roadtx is installed. This is
        more reliable than Get-Command because pip --user scripts may not be
        on PATH in all sessions.

    .EXAMPLE
        Test-RoadtxInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        roadtx is installed via pip install --user roadtx.
    #>
    [CmdletBinding()]
    param()

    python -m pip show roadtx 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-RoadtoolsHybridInstalled {
    <#
    .SYNOPSIS
        Tests whether roadtools_hybrid has been cloned into the tools folder.

    .DESCRIPTION
        Checks for the presence of the roadtools_hybrid directory under the
        specified ToolsPath. Returns $true if the folder exists, $false
        otherwise.

    .PARAMETER ToolsPath
        The root path where tools are installed (e.g., Desktop\DJMTools).

    .EXAMPLE
        Test-RoadtoolsHybridInstalled -ToolsPath 'C:\Users\User\Desktop\DJMTools'

    .OUTPUTS
        System.Boolean

    .NOTES
        Presence of the folder is used as proxy for successful clone.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolsPath
    )

    $hybridPath = Join-Path -Path $ToolsPath -ChildPath 'roadtools_hybrid'
    return Test-Path -Path $hybridPath
}

function Test-MSGraphInstalled {
    <#
    .SYNOPSIS
        Tests whether the Microsoft.Graph PowerShell module is available.

    .DESCRIPTION
        Uses Get-Module -ListAvailable to check for the Microsoft.Graph module.
        Returns $true if found, $false otherwise.

    .EXAMPLE
        Test-MSGraphInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param()

    return [bool](Get-Module -Name 'Microsoft.Graph' -ListAvailable -ErrorAction SilentlyContinue)
}

function Test-AzureADInstalled {
    <#
    .SYNOPSIS
        Tests whether the AzureAD PowerShell module is available.

    .DESCRIPTION
        Uses Get-Module -ListAvailable to check for the AzureAD module.
        Returns $true if found, $false otherwise.

    .EXAMPLE
        Test-AzureADInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        AzureAD module is optional. The caller should treat absence as a warning,
        not a failure.
    #>
    [CmdletBinding()]
    param()

    return [bool](Get-Module -Name 'AzureAD' -ListAvailable -ErrorAction SilentlyContinue)
}

function Test-MimikatzInstalled {
    <#
    .SYNOPSIS
        Tests whether mimikatz.exe exists in the tools folder.

    .DESCRIPTION
        Checks for the presence of mimikatz.exe under ToolsPath\mimikatz\x64\.
        Returns $true if found, $false otherwise.

    .PARAMETER ToolsPath
        The root path where tools are installed (e.g., Desktop\DJMTools).

    .EXAMPLE
        Test-MimikatzInstalled -ToolsPath 'C:\Users\User\Desktop\DJMTools'

    .OUTPUTS
        System.Boolean

    .NOTES
        The zip from github.com/gentilkiwi/mimikatz/releases extracts to an
        x64 subdirectory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolsPath
    )

    $mimikatzExe = Join-Path -Path $ToolsPath -ChildPath 'mimikatz\x64\mimikatz.exe'
    return Test-Path -Path $mimikatzExe
}

function Test-PostmanInstalled {
    <#
    .SYNOPSIS
        Tests whether Postman is installed.

    .DESCRIPTION
        Checks for Postman.exe at known winget user-scope install paths.
        Checks both the Programs subdirectory layout and the flat Postman
        layout used by different installer versions.

    .EXAMPLE
        Test-PostmanInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        Postman is not added to PATH on install, so Get-Command is not reliable.
    #>
    [CmdletBinding()]
    param()

    $postmanPaths = @(
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Postman\Postman.exe'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Postman\Postman.exe')
    )
    return [bool]($postmanPaths | Where-Object { Test-Path -Path $_ })
}

function Test-AzureCLIInstalled {
    <#
    .SYNOPSIS
        Tests whether the Azure CLI is installed and available on PATH.

    .DESCRIPTION
        Uses Get-Command to check for the 'az' executable on the current PATH.
        Returns $true if found, $false otherwise.

    .EXAMPLE
        Test-AzureCLIInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        Azure CLI is installed machine-wide via winget (Microsoft.AzureCLI).
    #>
    [CmdletBinding()]
    param()

    return [bool](Get-Command -Name 'az' -ErrorAction SilentlyContinue)
}

function Test-OpenVPNInstalled {
    <#
    .SYNOPSIS
        Tests whether the OpenVPN client is installed.

    .DESCRIPTION
        Checks for openvpn-gui.exe at known install paths: machine-wide x64
        and x86. Returns $true if found at any path.

    .EXAMPLE
        Test-OpenVPNInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        OpenVPN is not reliably added to PATH, so Get-Command is not used.
    #>
    [CmdletBinding()]
    param()

    $openVpnPaths = @(
        (Join-Path -Path ${env:ProgramFiles} -ChildPath 'OpenVPN\bin\openvpn-gui.exe'),
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'OpenVPN\bin\openvpn-gui.exe')
    )
    return [bool]($openVpnPaths | Where-Object { Test-Path -Path $_ })
}

function Test-FirefoxInstalled {
    <#
    .SYNOPSIS
        Tests whether Mozilla Firefox is installed.

    .DESCRIPTION
        Checks for firefox.exe at known install paths: machine-wide x64,
        machine-wide x86, and per-user. Returns $true if found at any path.

    .EXAMPLE
        Test-FirefoxInstalled

    .OUTPUTS
        System.Boolean

    .NOTES
        Firefox is not reliably added to PATH, so Get-Command is not used.
    #>
    [CmdletBinding()]
    param()

    $firefoxPaths = @(
        (Join-Path -Path ${env:ProgramFiles} -ChildPath 'Mozilla Firefox\firefox.exe'),
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Mozilla Firefox\firefox.exe'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Mozilla Firefox\firefox.exe')
    )
    return [bool]($firefoxPaths | Where-Object { Test-Path -Path $_ })
}

#endregion



#region Main Execution

Function Install-Holger {

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [switch]$LoadFunctionsOnly
    )

    $script:DJMToolsRoot = Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath 'DJMTools'
    $script:LogDirectory = Join-Path -Path $script:DJMToolsRoot -ChildPath 'logs'
    $script:LogFilePath = $null

    # UTF-8 output encoding so winget progress bar characters render correctly
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8

    $logPath = Initialize-ScriptLogging -ScriptTag 'install-djmtools'
    Write-StatusByPrefix "[i] Logging to: $logPath"
    Write-LogEntry -Message 'Install-DJMTools execution started.'

    # Admin guard
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error -Message 'This script must be run as Administrator. Exiting.' -ErrorAction Stop
    }

    # Defender: disable real-time monitoring and add exclusions
    Write-StatusByPrefix '[i] Disabling Windows Defender real-time monitoring...'
    Set-MpPreference -DisableRealtimeMonitoring $true

    $exclusionPaths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads'),
        # pip --user install destinations for packages and scripts
        (Join-Path -Path $env:APPDATA -ChildPath 'Python'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs'),
        # pip download staging area (impacket and similar get flagged here)
        $env:TEMP
    )

    # ToolsPath added after creation below
    $ToolsPath = Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath 'DJMTools'

    $exclusionPaths += $ToolsPath

    foreach ($exclusionPath in $exclusionPaths) {
        Write-StatusByPrefix "[i] Adding Defender exclusion: $exclusionPath"
        Add-MpPreference -ExclusionPath $exclusionPath
    }

    # Ensure ToolsPath exists
    if (-not (Test-Path -Path $ToolsPath)) {
        New-Item -ItemType Directory -Path $ToolsPath | Out-Null
        Write-StatusByPrefix "[+] Created tools directory: $ToolsPath"
    }

    # --- Python 3.13 ---
    Write-StatusByPrefix '[>] Checking Python...'
    if (-not (Test-PythonInstalled)) {
        Write-StatusByPrefix '[+] Installing Python 3.13...'
        $exitCode = Invoke-WingetInstall -PackageId 'Python.Python.3.13'
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($exitCode -ne 0) {
            Write-Warning -Message "Python installation exited with code $exitCode. Pip-dependent tools may fail."
        }
        Confirm-InstalledState -ToolName 'Python' -TestScript { Test-PythonInstalled } | Out-Null
    }
    else {
        Write-StatusByPrefix '[x] Python already installed.'
    }







    # Ensure pip --user script location is on PATH
    $pythonUserScriptsPath = Join-Path -Path $env:APPDATA -ChildPath 'Python\Python313\Scripts'
    if (Add-UserPathEntryIfMissing -PathEntry $pythonUserScriptsPath) {
        Write-StatusByPrefix "[x] User PATH includes: $pythonUserScriptsPath"
    }
    else {
        Write-Warning -Message "Python scripts path not found, PATH unchanged: $pythonUserScriptsPath"
    }




    Write-StatusByPrefix ''
    Write-StatusByPrefix '[x] DJMTools installation complete.'
    Write-StatusByPrefix "[i] Tools directory: $ToolsPath"

    #endregion

}
