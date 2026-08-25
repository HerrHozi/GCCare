<#
.SYNOPSIS
Converts Tanita body measurement CSV data into Garmin-compatible FIT files.

.DESCRIPTION
Convert-TanitaExportToFitFile validates a Tanita CSV export, resolves the output directory,
and calls the bundled Python conversion script to generate one or more FIT files.

If no CSV file is provided, the function opens a file picker so that an input file
can be selected interactively. The function also validates that Python is available
through either py.exe or python.exe on PATH before starting the conversion.

.PARAMETER csvFile
Path to the Tanita CSV input file. Only .csv files are accepted. If omitted, the
function prompts for a file by using a Windows file selection dialog.

.PARAMETER outputDirectory
Directory where the generated FIT files will be written. If the directory does not
exist, it is created automatically. The default is the current working directory.

.PARAMETER HeightCm
Body height in centimeters. This value is passed to the Python converter and must
be greater than zero. The default value is 178.0.

.PARAMETER LastX
Limits the conversion to the most recent number of measurements in the CSV file.
When specified, the value must be greater than zero.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv'

Converts all measurements in the specified CSV file and writes the generated FIT
files to the current directory.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -outputDirectory 'C:\Data\Tanita\Fit' -HeightCm 180 -LastX 7

Converts only the latest seven measurements, uses a height of 180 cm during the
conversion, and writes the resulting FIT files to the specified output directory.

.NOTES
Requires the bundled Python script Corefunctions\Convert_Last_x_tanita_measurements_to_fit.py
and a Python installation that is accessible through py.exe or python.exe.

.LINK
https://github.com/Jacopo1891/fit2garmin
https://github.com/cyberjunky/python-garminconnect
https://www.fitfileviewer.com/
#>
Function Convert-TanitaExportToFitFile {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidatePattern('(?i)\.csv$')]
        [string]$csvFile,
        [string]$outputDirectory = $Script:DefaultFitFilesFolder,
        [double]$HeightCm = 178.0,
        [int]$LastX,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Converting Tanita CSV to FIT files ..."

    if (-not $csvFile) {
        Add-Type -AssemblyName System.Windows.Forms

        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Select csv input file"
        $dialog.Filter = "csv files (*.csv)|*.csv"
        $dialog.Multiselect = $false
        $dialog.CheckFileExists = $true
        $dialog.InitialDirectory = (Get-Location).Path

        $dialogResult = $dialog.ShowDialog()
        if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.FileName)) {
            Invoke-Output -Type Missing -Message "No CSV file selected. Script canceled."
            return
        }

        $csvFile = $dialog.FileName
    }

    if (-not (Test-Path -LiteralPath $csvFile -PathType Leaf)) {
        invoke-output -type Missing -message "CSV file not found: " -Textmaker "$csvFile"
        return
    }

    if ([System.IO.Path]::GetExtension($csvFile) -notmatch '^(?i)\.csv$') {
        invoke-output -type Missing -message "Only .csv files are allowed: " -Textmaker "$csvFile"
        return
    }

    $csvFile = (Resolve-Path -LiteralPath $csvFile).Path

    Invoke-Output -Type Bullet -Message "Input CSV file:  " -Textmaker "$csvFile"

    If (-not $outputDirectory) {
        $outputDirectory = $Script:DefaultFitFilesFolder
    }    
    $outputDirectory = [System.IO.Path]::GetFullPath($outputDirectory)

    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        $null = New-Item -Path $outputDirectory -ItemType Directory -Force
    }

    Invoke-Output -Type Bullet -Message "Output directory:" -Textmaker "$outputDirectory"
    Write-host

    if ($HeightCm -le 0) {
        throw 'HeightCm must be greater than zero.'
    }

    if ($PSBoundParameters.ContainsKey('LastX') -and $LastX -le 0) {
        throw 'Last X must be greater than zero.'
    }

    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $pythonScriptPath = Join-Path -Path $moduleRoot -ChildPath 'Corefunctions\Convert_Last_x_tanita_measurements_to_fit.py'

    if (-not (Test-Path -LiteralPath $pythonScriptPath -PathType Leaf)) {
        invoke-output -type Missing -message "Python script not found: $pythonScriptPath"
        #Write-Host "  [!] Python script not found: $pythonScriptPath" -ForegroundColor Yellow
        return
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
        '--input-csv'
        $csvFile
        '--output-dir'
        $outputDirectory
        '--height-cm'
        $HeightCm.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    )

    if ($PSBoundParameters.ContainsKey('LastX')) {
        $pythonArguments += @('--last-x', $LastX)
    }

    & $pythonCommand @pythonArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Python script failed with exit code $LASTEXITCODE."
    }

    Invoke-Output -Type Success -Message "Conversion completed successfully. `n       FIT files are located in: $outputDirectory"
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}