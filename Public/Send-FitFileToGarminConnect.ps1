<#
.SYNOPSIS
Uploads FIT files from a local folder to Garmin Connect.

.DESCRIPTION
`Send-FitFileToGarminConnect` validates the selected import directory, checks for
available `.fit` files, and executes the bundled Python uploader script
`Corefunctions\upload_fit_files_minimal.py`.

The function automatically detects a Python executable (`py` or `python`) from PATH.
If a token store path is provided, it is forwarded to the uploader script.

.PARAMETER ImportDirectory
Path to the folder containing `.fit` files.
If omitted, the module default FIT folder is used.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store file/folder used by the Python uploader.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
None
Writes progress and result messages to output helpers and throws on validation/upload errors.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`.
- Requires Python (`py.exe` or `python.exe`) available in PATH.
- Requires the bundled script:
  `<ModuleRoot>\Corefunctions\upload_fit_files_minimal.py`.
- Upload is delegated to the Python script; non-zero exit codes are treated as errors.

.EXAMPLE
Send-FitFileToGarminConnect -ImportDirectory "C:\Data\Garmin\Fit"

Uploads all FIT files from the specified folder.

.EXAMPLE
Send-FitFileToGarminConnect -ImportDirectory "C:\Data\Garmin\Fit" -TokenStore "C:\Temp\.garminconnect"

Uploads all FIT files from the specified folder using a custom token store.
#>
Function Send-FitFileToGarminConnect {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$ImportDirectory = $Script:DefaultFitFilesFolder,
        [string]$TokenStore,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Uploading FIT files to Garmin Connect..."

    if (-not $ImportDirectory) {
        $ImportDirectory = $Script:DefaultFitFilesFolder
    }

    $ImportDirectory = [System.IO.Path]::GetFullPath($ImportDirectory)

    if (-not (Test-Path -LiteralPath $ImportDirectory -PathType Container)) {
        throw "Import directory not found: $ImportDirectory"
    }

    $fitFiles = Get-ChildItem -LiteralPath $ImportDirectory -Filter '*.fit' -File -ErrorAction SilentlyContinue
    if (-not $fitFiles -or $fitFiles.Count -eq 0) {
        throw "No .fit files found in import directory: $ImportDirectory"
    }

    Invoke-Output -Type Bullet -Message "Import directory: " -textmaker $ImportDirectory
    Invoke-Output -Type Bullet -Message "FIT files found:  " -textmaker $($fitFiles.Count)

    Write-host
    
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $pythonScriptPath = Join-Path -Path $moduleRoot -ChildPath 'Corefunctions\upload_fit_files_minimal.py'

    if (-not (Test-Path -LiteralPath $pythonScriptPath -PathType Leaf)) {
        throw "Python script not found: $pythonScriptPath"
    }

    $pythonCommand = $null
    foreach ($candidate in @('py', 'python')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            $pythonCommand = $command.Source
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($pythonCommand)) {
        throw 'Python executable not found. Install Python and ensure py.exe or python.exe is in PATH.'
    }

    $pythonArguments = @(
        $pythonScriptPath
        '--folder'
        $ImportDirectory
    )

    if ($PSBoundParameters.ContainsKey('TokenStore') -and -not [string]::IsNullOrWhiteSpace($TokenStore)) {
        $pythonArguments += @('--tokenstore', $TokenStore)
    }

    & $pythonCommand @pythonArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Python script failed with exit code $LASTEXITCODE."
    }

    Invoke-Output -Type Success -Message "FIT upload completed successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}