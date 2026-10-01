<#
.SYNOPSIS
Converts Tanita body measurement CSV data into Garmin-compatible FIT files.

.DESCRIPTION
Convert-TanitaExportToFitFile validates a Tanita CSV export, resolves the output directory,
and writes one Garmin weight FIT file per measurement directly from PowerShell.
Each file contains a file_id and a weight_scale message.

If no CSV file is provided, the function opens a file picker so that an input file
can be selected interactively. Measurements with missing values ('-') are skipped.

Written weight_scale values: weight, percent fat, percent hydration, bone mass (filled with
the body fat mass in kg), muscle mass, BMI, visceral fat rating, metabolic age,
physique rating, basal/active metabolic rate (2000 kcal) and user profile index 0.

.PARAMETER csvFile
Path to the Tanita CSV input file. Only .csv files are accepted. If omitted, the
function prompts for a file by using a Windows file selection dialog.

.PARAMETER outputDirectory
Directory where the generated FIT files will be written. If the directory does not
exist, it is created automatically. The default is C:\Users\Public\GCCare\FitFiles.

.PARAMETER HeightCm
Body height in centimeters, used to calculate the BMI when the CSV has no BMI value.
Must be greater than zero. The default value is 178.0.

.PARAMETER LastX
Limits the conversion to the most recent number of measurements in the CSV file.
If omitted, the function asks for the number of entries.

.PARAMETER Upload
Uploads the created FIT files directly to Garmin Connect (requires a token created by
Get-GarminToken).

.PARAMETER TokenStore
Optional path to the Garmin token store directory or garmin_tokens.json file (used with -Upload).

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -LastX 7

Converts the latest seven measurements and writes the FIT files to C:\Users\Public\GCCare\FitFiles.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -outputDirectory 'C:\Data\Tanita\Fit' -HeightCm 180 -LastX 7

Converts only the latest seven measurements, uses a height of 180 cm for missing BMI values,
and writes the resulting FIT files to the specified output directory.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -LastX 1 -Upload

Converts the latest measurement and uploads it to Garmin Connect.

.NOTES
Requires the private helpers New-GarminWeightFitFile (FIT encoder) and, for -Upload,
Invoke-GarminConnectApi.

.LINK
https://developer.garmin.com/fit/protocol/
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
        [switch]$Upload,
        [string]$TokenStore,
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

    if (-not $PSBoundParameters.ContainsKey('LastX')) {
        $answer = Invoke-Output -Type Input -Message "How many of the latest entries should be exported?"
        if (-not [int]::TryParse($answer, [ref]$LastX) -or $LastX -le 0) {
            throw 'The number of entries must be greater than zero.'
        }
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $heightM = $HeightCm / 100.0
    $requiredColumns = 'Date', 'Weight (kg)', 'Body Fat (%)', 'Body Water (%)', 'Muscle Mass (kg)', 'Metab Age', 'Visc Fat', 'Physique Rating'

    $rows = @(Import-Csv -LiteralPath $csvFile -Encoding UTF8)
    if ($rows.Count -eq 0) {
        Invoke-Output -Type Missing -Message "CSV file contains no measurements: " -TextMaker "$csvFile"
        return
    }

    $missingColumns = $requiredColumns | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }
    if ($missingColumns) {
        throw "CSV file is missing required columns: $($missingColumns -join ', ')"
    }

    $createdFiles = @()
    foreach ($row in ($rows | Select-Object -Last $LastX)) {
        # Tanita exports '-' for values that were not measured
        $values = @{}
        foreach ($column in $requiredColumns | Where-Object { $_ -ne 'Date' }) {
            $number = 0.0
            if (-not [double]::TryParse($row.$column, [System.Globalization.NumberStyles]::Float, $invariant, [ref]$number)) {
                $number = $null
            }
            $values[$column] = $number
        }
        if ($values.Values -contains $null) {
            Invoke-Output -Type Missing -Message "Skipped incomplete measurement: " -TextMaker "$($row.Date)" -NoExtraLines
            continue
        }

        $timestamp = [datetime]::ParseExact($row.Date, 'yyyy-MM-dd HH:mm:ss', $invariant)
        $weight = $values['Weight (kg)']
        $fatPercent = $values['Body Fat (%)']

        $bmi = 0.0
        if (-not [double]::TryParse($row.BMI, [System.Globalization.NumberStyles]::Float, $invariant, [ref]$bmi)) {
            $bmi = [math]::Round($weight / ($heightM * $heightM), 2)
        }

        $fitParams = @{
            Path              = Join-Path -Path $outputDirectory -ChildPath ("weight_{0:yyyy-MM-dd_HH-mm}.fit" -f $timestamp)
            Timestamp         = $timestamp
            Weight            = $weight
            PercentFat        = $fatPercent
            PercentHydration  = $values['Body Water (%)']
            # Intentional: the bone_mass field carries the body fat mass in kg (do not change)
            BoneMass          = [math]::Round($weight * ($fatPercent / 100.0), 2)
            MuscleMass        = $values['Muscle Mass (kg)']
            Bmi               = $bmi
            VisceralFatRating = [int][math]::Truncate($values['Visc Fat'])
            MetabolicAge      = [int][math]::Truncate($values['Metab Age'])
            PhysiqueRating    = [int][math]::Truncate($values['Physique Rating'])
            BasalMet          = 2000
            ActiveMet         = 2000
        }

        $fitFile = New-GarminWeightFitFile @fitParams
        $createdFiles += $fitFile
        Invoke-Output -Type Bullet -Message "FIT file created:" -TextMaker $fitFile.Name -NoExtraLines
        Write-Log -Message "    >> FIT file created: $($fitFile.FullName)"
    }

    if ($Upload -and $createdFiles.Count -gt 0) {
        Write-Host
        foreach ($fitFile in $createdFiles) {
            try {
                $null = Invoke-GarminConnectApi -Path '/upload-service/upload' -Method Post -Form @{ file = $fitFile } -TokenStore $TokenStore
                Invoke-Output -Type Bullet -Message "Uploaded:        " -TextMaker $fitFile.Name -NoExtraLines
            }
            catch {
                Invoke-Output -Type Missing -Message "Upload failed:   " -TextMaker "$($fitFile.Name) - $($_.Exception.Message)" -NoExtraLines
            }
        }
    }

    Invoke-Output -Type Success -Message "Conversion completed successfully ($($createdFiles.Count) files). `n       FIT files are located in: $outputDirectory"
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}