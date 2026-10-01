################################################################################
######                                                                     #####
######                            GCCare Module                            #####
######                                                                     #####
################################################################################
<#
.SYNOPSIS
GCCare is a PowerShell module to maintain the Garmin Connect settings.

.DESCRIPTION

GCCare is written in pure PowerShell. It signs in to Garmin Connect, calls the
Garmin Connect API and includes fitness-related utilities (for example:
Tanita CSV -> FIT conversion, FIT upload and TCX analysis).

.MODULE STRUCTURE
- Public\   : exported user commands
- Private\  : internal helper functions
- Common\   : shared utilities

.RUNTIME BEHAVIOR
On import, the module:
1. Initializes global script settings (dates, colors, paths, logging flags)
2. Loads all scripts from Private/Public/Common
3. Exports public functions (and aliases, if defined)
4. Optionally exports private functions when GCCare_EXPORT_PRIVATE=1
5. Ensures required folders exist under $env:PUBLIC\GCCare
6. Copies the default configuration (GCCare.json) if it does not exist yet
7. Shows module banner/version and quick-start hints

.DEFAULT DIRECTORIES
- Logs:      $env:PUBLIC\GCCare\Logs
- Temp:      $env:PUBLIC\GCCare\Temp
- Config:    $env:PUBLIC\GCCare\Config
- CleanUp:   $env:PUBLIC\GCCare\CleanUp
- FitFiles:  $env:PUBLIC\GCCare\FitFiles

.REQUIREMENTS
- Windows
- PowerShell 7.1 or later
- Garmin Connect commands: token store created by Get-GarminToken
  (default: ~\.garminconnect\garmin_tokens.json)

.NOTES
Author: HerrHozi | zimmermann.holger@live.de
#>

$Script:DateFormatLog = "yyyy-MM-dd HH:mm:ss.fff"
$Script:DateFormatSA = "yyyy-MM-dd HH:mm:ss"

$Script:WinVersion = [System.Environment]::OSVersion.Version.ToString()

$GGCModulePath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$GGCModuleTopPath = Split-Path -Path $GGCModulePath -Parent
$GGCModuleName = $MyInvocation.MyCommand.ScriptBlock.Module.Name

$GGCModuleManifest = (Test-ModuleManifest -Path $(join-path $GGCModulePath -ChildPath "\$GGCModuleName.psd1"))
$GGCModuleLastUpdate = $GGCModuleManifest.PrivateData.PSData.LastUpdate

$script:GCCarePublicDir = Join-Path -Path $env:PUBLIC -ChildPath "GCCare"
$Script:GCCareLogDir = Join-Path -Path $script:GCCarePublicDir -ChildPath "Logs"
$Script:GCCareTempDir = Join-Path -Path $script:GCCarePublicDir -ChildPath "Temp"
$Script:GCCareConfigDir = Join-Path -Path $script:GCCarePublicDir -ChildPath "Config"
$Script:DefaultCleanUpFolder = Join-Path -Path $script:GCCarePublicDir -ChildPath "CleanUp"
$Script:DefaultFitFilesFolder = Join-Path -Path $script:GCCarePublicDir -ChildPath "FitFiles"


$Script:ASModuleLog = Join-Path -Path $Script:GCCareLogDir -ChildPath "GCCare.log"
$Script:ConfigFile = Join-Path -Path $Script:GCCareConfigDir -ChildPath "GCCare.json"


If ($PSVersionTable.PSVersion.Major -ge 7) {
    $Script:PoSH7 = $true
    # --- Global header color for all Format-Table outputs ---
    $PSStyle.Formatting.TableHeader = "`e[90m"   # DarkGray
    #Cyan → "e[96m"
    #White → "e[97m"
}

$Script:FGCIInfo = [System.ConsoleColor]::Magenta    # Additional info / side details
$Script:FGCMInfo = [System.ConsoleColor]::Yellow       # Main info (instead of Yellow → modern, easy to read)
$Script:FGCSInfo = [System.ConsoleColor]::DarkGray   # Secondary info / less important
$Script:FGCCommand = [System.ConsoleColor]::White      # Commands / executions
$Script:FGCQuestion = [System.ConsoleColor]::Cyan
$Script:FGCInput = [System.ConsoleColor]::Cyan
$Script:FGCDecisionPrompt = [System.ConsoleColor]::Cyan    # Questions / user input
$Script:FGCHighLight = [System.ConsoleColor]::Magenta      # Clear highlight text
$Script:FGCWarning = [System.ConsoleColor]::Cyan      # Warnings (classic Yellow)
$Script:FGCError = [System.ConsoleColor]::Red        # Errors (bright red tone, more visible)

$Script:ConsoleBGColor = [System.ConsoleColor]::Black
$Script:ConsoleFGColor = [System.ConsoleColor]::Gray

$Script:fgcS = "DarkGray"    # Switch - DarkGray
$Script:fgcC = "Yellow"      # Command
$Script:fgcV = "White"       # Value"DarkCyan"    # Value Blue or Cyan
$Script:fgcF = "White"       # Foreground Color
$Script:fgcR = "Green"       # Result
$Script:fgcHeader = [System.ConsoleColor]::DarkGray

$Script:Yes = "Y"
$Script:No = "N"
$Script:EnableLogging = $false


##########################################################################

Set-Alias Pause Invoke-NextStep -Force

$ScriptDir = New-Object System.Collections.ArrayList

if (Test-Path("$GGCModulePath\Private")) {
    $PrivatePath = '{0}\Private\*.ps1' -f $GGCModulePath
    [VOID]$ScriptDir.Add($PrivatePath)
}
if (Test-Path("$GGCModulePath\Public")) {
    $PublicPath = '{0}\Public\*.ps1' -f $GGCModulePath
    [VOID]$ScriptDir.Add($PublicPath)
}
if (Test-Path("$GGCModulePath\Common")) {
    $CommonPath = '{0}\Common\*.ps1' -f $GGCModulePath
    [VOID]$ScriptDir.Add($CommonPath)
}

$Scripts = Get-ChildItem -Path $ScriptDir | Select-Object -ExpandProperty FullName

# Load all scripts in the module
foreach ($Script in $Scripts) {
    . $Script
}

#$SearchRecursive = $true
$SearchRootOnly = $false
$PublicScriptBlock = [ScriptBlock]::Create((Get-ChildItem -Path $PublicPath | Get-Content | Out-String))
$PublicFunctionAsts = $PublicScriptBlock.Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $SearchRootOnly)
$PublicFunctions = $PublicFunctionAsts.Name

If ($env:GCCare_EXPORT_PRIVATE -eq 1) {
    $ExportPrivateFunctions = $true
}
else {
    $ExportPrivateFunctions = $false
}

# Export all functions including alias
if ($PublicFunctions) {
    foreach ($Function in $PublicFunctions) {
        $Alias = @()

        #Check if function has an alias
        $AliasFunc = $PublicFunctionAsts | Where-Object { $_.Name -eq $Function -and $_.Body.ParamBlock -and $_.Body.ParamBlock.Attributes } | Select-Object -First 1
        #Check if an alias was found, if it did save the alias name
        if ($AliasFunc) {
            $Alias = $AliasFunc.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' } | ForEach-Object { $_.PositionalArguments.Value } | Where-Object { $_ }
        }

        #If alias exist export function wiht alias
        if ($Alias) {
            Export-ModuleMember -Function $Function -Alias $Alias
        }
        else {
            Export-ModuleMember -Function $Function
        }

    }
}

if ($ExportPrivateFunctions -and $PrivatePath) {
    $PrivateFilePattern = Join-Path -Path $GGCModulePath -ChildPath 'Private\*.ps1'
    $PrivateFunctions = Get-Command -CommandType Function |
    Where-Object {
        $_.ScriptBlock -and
        $_.ScriptBlock.File -and
        ($_.ScriptBlock.File -like $PrivateFilePattern)
    } |
    Select-Object -ExpandProperty Name -Unique

    if ($PrivateFunctions) {
        foreach ($Function in $PrivateFunctions) {
            Export-ModuleMember -Function $Function -ErrorAction SilentlyContinue
        }
    }
}

Invoke-GCCareDirectory -Directory $Script:GCCareLogDir
Invoke-GCCareDirectory -Directory $Script:GCCareTempDir
Invoke-GCCareDirectory -Directory $Script:GCCareConfigDir
Invoke-GCCareDirectory -Directory (Join-Path -Path $script:GCCarePublicDir -ChildPath "MaliciousTools")
Invoke-GCCareDirectory -Directory $Script:DefaultCleanUpFolder
Invoke-GCCareDirectory -Directory $Script:DefaultFitFilesFolder

If (-not (Test-Path -Path $Script:ConfigFile)) {
    copy-item "$GGCModulePath\GCCare.json" -Destination $Script:ConfigFile
}


Show-PiskelFile -PiskelPath (Join-Path -Path $GGCModulePath -ChildPath "GCCare.piskel") -addshadow

#Write-Host "`n"
Write-Host "  Description: $($GGCModuleManifest.Description) " -ForegroundColor Gray
Write-Host "  Author: HerrHozi | Version: $($GGCModuleManifest.Version) | Last Update: $GGCModuleLastUpdate | $($GGCModuleManifest.Copyright)" -ForegroundColor Gray
Write-Host "`n  get-command " -NoNewline -ForegroundColor DarkYellow
Write-Host "-Module " -ForegroundColor DarkGray -NoNewline
Write-Host "'GCCare'`n`n" -ForegroundColor DarkCyan


#Write-Host "  Description:     $($GGCModuleManifest.Description) " -ForegroundColor Gray
#Write-Host "  Version:         $($GGCModuleManifest.Version) | Last Update: $GGCModuleLastUpdate | Author: $($GGCModuleManifest.Author) " -ForegroundColor Gray
Write-Host "`n  [>] Quick-Start: " -NoNewline -ForegroundColor Gray 

Write-HighlightedCode  -code "Update-TCXFile"
Write-HighlightedCode  -code "                   Convert-TanitaExportToFitFile"
Write-HighlightedCode  -code "                   Get-GarminToken"
Write-HighlightedCode  -code "                   Send-FitFileToGarminConnect"
Write-HighlightedCode  -code "                   Get-WeeklyBodyMetrics"
Write-HighlightedCode  -code "                   Invoke-TCXFileAnalysis | Select-Object Lap, TotalDistance, TotalTime,  Laptime, MovingTime, NonMovingTime, AscentMeters, DescentMeters, TotalAscentMeters, TotalDescentMeters | ft"
Write-HighlightedCode  -code "                   Get-GarminBadges -GroupBy Month | Where-Object {`$_.Year -eq 2025} | ft"
Write-HighlightedCode  -code "                   Get-GarminUser | Ft"

Write-host "`n"
$host.ui.RawUI.WindowTitle = "$GGCModuleName - $($GGCModuleManifest.Version)"
