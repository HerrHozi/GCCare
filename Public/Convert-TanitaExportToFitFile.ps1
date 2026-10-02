<#
.SYNOPSIS
Converts Tanita (RD-545) body measurement CSV data into Garmin-compatible FIT files.

.DESCRIPTION
Convert-TanitaExportToFitFile validates a Tanita CSV export, resolves the output directory,
and writes one Garmin weight FIT file per measurement directly from PowerShell.
Each file contains a file_id and a weight_scale message.

If no CSV file is provided, the function opens a file picker so that an input file
can be selected interactively. Measurements with missing values ('-') are skipped.

Column names:
The CSV column for each value is taken from the section "MeasurementHeaders" in the user
configuration $env:USERPROFILE\GCCare\Config\GCCare.json. The key is fixed, the value is the
column name in your CSV file, so exports with other column names - e.g. from German
systems - can be used without changes:

    "MeasurementHeaders": {
        "Date": "Datum",
        "Weight (kg)": "Gewicht (kg)",
        "Body Fat (%)": "Fettanteil (%)",
        ...
    }

Keys: Date, Weight (kg), Body Fat (%), Body Water (%), Muscle Mass (kg), Metab Age,
Visc Fat, Physique Rating, BMR (kcal), BMI. Keys that are missing in GCCare.json keep the
default Tanita column name (identical to the key). -HeaderMapping overrides single
columns for one call. The BMI column is optional; without it the BMI is calculated from
-HeightCm.

CSV format:
- Delimiter ',' or ';' (detected automatically from the header line).
- Decimal separator '.' or ','.
- Date formats yyyy-MM-dd HH:mm[:ss], dd.MM.yyyy HH:mm[:ss], yyyy/MM/dd HH:mm:ss,
  dd/MM/yyyy HH:mm:ss or any format of the current culture.

Written weight_scale values: weight, percent fat, percent hydration, bone mass (filled with
the body fat mass in kg), muscle mass, BMI, visceral fat rating, metabolic age,
physique rating, basal/active metabolic rate and user profile index 0.

.PARAMETER csvFile
Path to the Tanita CSV input file. Only .csv files are accepted. If omitted, the
function prompts for a file by using a Windows file selection dialog.

.PARAMETER outputDirectory
Directory where the generated FIT files will be written. If the directory does not
exist, it is created automatically. The default is $env:USERPROFILE\GCCare\FitFiles.

.PARAMETER HeightCm
Body height in centimeters, used to calculate the BMI when the CSV has no BMI column or
no BMI value. Must be greater than zero. The default value is 178.0.

.PARAMETER LastX
Limits the conversion to the most recent number of measurements in the CSV file.
If omitted, the function asks for the number of entries.

.PARAMETER Upload
Uploads the created FIT files directly to Garmin Connect with Send-FitFileToGarminConnect and
moves them to the subfolder Uploaded of the output directory (requires a token created by
Get-GarminToken).

.PARAMETER HeaderMapping
Optional hashtable that overrides CSV column names for this call only, e.g.
@{ 'Date' = 'Datum'; 'Weight (kg)' = 'Gewicht' }. Takes precedence over "MeasurementHeaders"
in GCCare.json. Only the keys listed in the description are allowed.

.PARAMETER TokenStore
Optional path to the Garmin token store directory or gctoken.json file (used with -Upload).

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -LastX 7

Converts the latest seven measurements and writes the FIT files to $env:USERPROFILE\GCCare\FitFiles.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -outputDirectory 'C:\Data\Tanita\Fit' -HeightCm 180 -LastX 7

Converts only the latest seven measurements, uses a height of 180 cm for missing BMI values,
and writes the resulting FIT files to the specified output directory.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\bodydata.csv' -LastX 1 -Upload

Converts the latest measurement, uploads it to Garmin Connect and moves the FIT file to
$env:USERPROFILE\GCCare\FitFiles\Uploaded.

.EXAMPLE
PS> Convert-TanitaExportToFitFile -csvFile 'C:\Data\Tanita\messwerte.csv' -LastX 7 -HeaderMapping @{ 'Date' = 'Datum'; 'Weight (kg)' = 'Gewicht (kg)' }

Converts a German export whose date and weight columns have different names; all other
columns are taken from "MeasurementHeaders" in GCCare.json.

.NOTES
Requires the private helpers New-GarminWeightFitFile (FIT encoder) and
Get-GCCareMeasurementHeaders (column mapping) and, for -Upload, Send-FitFileToGarminConnect.
Existing user configurations created before "MeasurementHeaders" was added keep working with
the default column names; copy the section from the module's GCCare.json to customize them.

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
        [hashtable]$HeaderMapping,
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

    # Column names: defaults < GCCare.json "MeasurementHeaders" < -HeaderMapping
    $headers = Get-GCCareMeasurementHeaders -Mapping $HeaderMapping

    # Delimiter: ',' (English export) or ';' (e.g. German Excel/export), detected from the header line
    $headerLine = Get-Content -LiteralPath $csvFile -TotalCount 1 -Encoding UTF8
    $delimiter = if (([regex]::Matches($headerLine, ';')).Count -gt ([regex]::Matches($headerLine, ',')).Count) { ';' } else { ',' }
    Write-Log -Message "    >> CSV delimiter: '$delimiter'"

    $rows = @(Import-Csv -LiteralPath $csvFile -Delimiter $delimiter -Encoding UTF8)
    if ($rows.Count -eq 0) {
        Invoke-Output -Type Missing -Message "CSV file contains no measurements: " -TextMaker "$csvFile"
        return
    }

    $csvColumns = $rows[0].PSObject.Properties.Name
    # BMI is optional: when the column or a value is missing, it is calculated from -HeightCm
    $missingColumns = $headers.Keys | Where-Object { $_ -ne 'BMI' -and $headers[$_] -notin $csvColumns }
    if ($missingColumns) {
        $details = ($missingColumns | ForEach-Object { "'$($headers[$_])' ($_)" }) -join ', '
        throw ("CSV file is missing required columns: $details.`n" +
            "Adjust 'MeasurementHeaders' in $Script:ConfigFile or use -HeaderMapping. Columns in the CSV file: $($csvColumns -join ', ')")
    }

    # Numbers with '.' or ',' as decimal separator; '-' or empty means not measured
    function ConvertTo-MeasurementNumber([string]$Text) {
        $number = 0.0
        if ([double]::TryParse($Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $invariant, [ref]$number)) {
            return $number
        }
        return $null
    }

    $dateFormats = [string[]]('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', 'dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy HH:mm', 'yyyy/MM/dd HH:mm:ss', 'dd/MM/yyyy HH:mm:ss')

    $createdFiles = @()
    foreach ($row in ($rows | Select-Object -Last $LastX)) {
        $dateText = [string]$row.($headers['Date'])

        $values = @{}
        foreach ($key in $headers.Keys | Where-Object { $_ -notin 'Date', 'BMI' }) {
            $values[$key] = ConvertTo-MeasurementNumber $row.($headers[$key])
        }
        if ($values.Values -contains $null) {
            Invoke-Output -Type Missing -Message "Skipped incomplete measurement: " -TextMaker $dateText -NoExtraLines
            continue
        }

        $timestamp = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($dateText.Trim(), $dateFormats, $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$timestamp) -and
            -not [datetime]::TryParse($dateText, [ref]$timestamp)) {
            Invoke-Output -Type Missing -Message "Skipped measurement with unknown date format: " -TextMaker $dateText -NoExtraLines
            continue
        }

        $weight = $values['Weight (kg)']
        $fatPercent = $values['Body Fat (%)']

        $bmi = if ($headers['BMI'] -in $csvColumns) { ConvertTo-MeasurementNumber $row.($headers['BMI']) } else { $null }
        if (-not $bmi) {
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
            BasalMet          = $values['BMR (kcal)']
            ActiveMet         = 2000
        }

        $fitFile = New-GarminWeightFitFile @fitParams
        $createdFiles += $fitFile
        Invoke-Output -Type Bullet -Message "FIT file created:" -TextMaker $fitFile.Name -NoExtraLines
    }

    Invoke-Output -Type Success -Message "Conversion completed successfully ($($createdFiles.Count) files). `n       FIT files are located in: $outputDirectory"

    # Upload only the files created in this run; uploaded files are moved to <outputDirectory>\Uploaded
    if ($Upload -and $createdFiles.Count -gt 0) {
        $null = Send-FitFileToGarminConnect -Path $createdFiles.FullName -TokenStore $TokenStore
    }
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}