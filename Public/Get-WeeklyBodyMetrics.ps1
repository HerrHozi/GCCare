<#
.SYNOPSIS
Gets weekly body metrics averages from Tanita body composition CSV data.

.DESCRIPTION
Reads a Tanita CSV file, extracts relevant fields, calculates fat mass,
and groups entries by ISO calendar week.
Outputs weekly averages for weight, body fat, fat mass, muscle mass,
and segment muscle mass (left leg, right leg, trunk).

.NOTES
Expected CSV columns:
- Date
- Weight (kg)
- Body Fat (%)
- Muscle Mass (kg)
- Muscle mass - left leg
- Muscle mass - right leg
- Muscle mass - trunk

.EXAMPLE
PS> Get-WeeklyBodyMetrics
Opens a file picker for CSV files and prints weekly averages as a table.

.EXAMPLE
PS> Get-WeeklyBodyMetrics -CsvFile .\bodydata.csv
Uses the specified CSV file and prints weekly averages as a table.

.PARAMETER CsvFile
Path to the input CSV file. Only files with the .csv extension are accepted.

You can also use the aliases `BodyData`, `Path`, or the legacy alias `CsvPath`.

.PARAMETER Enablelogging
Optional switch to enable additional logging (project-dependent).
#>

Function Get-WeeklyBodyMetrics {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias('BodyData', 'Path', 'CsvPath')]
        [ValidatePattern('(?i)\.csv$')]
        [string]$CsvFile,
        [switch]$Enablelogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Calculating weekly averages for body composition data..."

    if (-not $CsvFile) {
        Add-Type -AssemblyName System.Windows.Forms

        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Select CSV input file"
        $dialog.Filter = "CSV files (*.csv)|*.csv"
        $dialog.Multiselect = $false
        $dialog.CheckFileExists = $true
        $dialog.InitialDirectory = (Get-Location).Path

        $dialogResult = $dialog.ShowDialog()
        if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.FileName)) {
            Write-Host "  [!] Canceled by user. No csv file was selected." -ForegroundColor Yellow
            return
        }

        $CsvFile = $dialog.FileName
    }

    if (-not (Test-Path -LiteralPath $CsvFile -PathType Leaf)) {
        throw "CSV file not found: $CsvFile"
    }

    if ([System.IO.Path]::GetExtension($CsvFile) -notmatch '^(?i)\.csv$') {
        throw "Only .csv files are allowed: $CsvFile"
    }

    $csvPath = (Resolve-Path -LiteralPath $CsvFile).Path

    Invoke-Output -Type Bullet -Message "Input CSV file:   " -Textmaker "$csvPath"

    # === Read CSV and extract fields ===
    $data = Import-Csv -Path $csvPath | ForEach-Object {
        $entry = $_

        $date = [datetime]$entry."Date"
        $weight = [double]$entry."Weight (kg)"
        $fatPercent = [double]$entry."Body Fat (%)"
        $muscleMass = [double]$entry."Muscle Mass (kg)"
        $leftLeg = [double]$entry."Muscle mass - left leg"
        $rightLeg = [double]$entry."Muscle mass - right leg"
        $trunk = [double]$entry."Muscle mass - trunk"
        $muscleMass = [double]$entry."Muscle Mass (kg)"
        $fatMass = [math]::Round($weight * ($fatPercent / 100.0), 2)

        [PSCustomObject]@{
            Date       = $date
            Weight     = $weight
            FatPercent = $fatPercent
            MuscleMass = $muscleMass
            LeftLeg    = $leftLeg
            RightLeg   = $rightLeg
            Trunk      = $trunk
            FatMass    = $fatMass
            Week       = [System.Globalization.CultureInfo]::InvariantCulture.Calendar.
            GetWeekOfYear($date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
        }
    }


    Invoke-Output -Type Bullet -Message "Number of entries:" -Textmaker $($data.Count)

    # === Group by week ===
    $dataGrouped = $data | Group-Object Week

    # === Weekly analysis ===
    $result = $dataGrouped | ForEach-Object {
        $group = $_.Group | Sort-Object Date
        $week = $_.Name

        [PSCustomObject]@{
            KW              = "KW$week"
            Count           = $group.Count
            From            = $group[0].Date.ToString("yyyy-MM-dd")
            To              = $group[-1].Date.ToString("yyyy-MM-dd")
            Ø_Weight_kg     = [math]::Round(($group | Measure-Object -Property Weight -Average).Average, 2)
            Ø_Fat_percent   = [math]::Round(($group | Measure-Object -Property FatPercent -Average).Average, 2)
            Ø_Fat_mass_kg   = [math]::Round(($group | Measure-Object -Property FatMass -Average).Average, 2)
            Ø_MuscleMass_kg = [math]::Round(($group | Measure-Object -Property MuscleMass -Average).Average, 2)
            Ø_LeftLeg_kg    = [math]::Round(($group | Measure-Object -Property LeftLeg -Average).Average, 2)
            Ø_RightLeg_kg   = [math]::Round(($group | Measure-Object -Property RightLeg -Average).Average, 2)
            Ø_Trunk_kg      = [math]::Round(($group | Measure-Object -Property Trunk -Average).Average, 2)
        }
    }

    # === Output ===
    $result | Format-Table -AutoSize

    Invoke-Output -Type Success -Message "Get-WeeklyBodyMetrics completed successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}


