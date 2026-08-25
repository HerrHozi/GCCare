<#
.SYNOPSIS
Updates a Garmin TCX activity file by recalculating and rewriting lap and trackpoint distance/elevation values.

.DESCRIPTION
This script loads an existing TCX activity and updates each lap using values from the
$ActivityLaps configuration table.

For each lap, it supports two input modes:
- Option A: Calculate lap distance and ascent from treadmill speed (km/h) and incline (%),
    based on the lap duration found in the TCX file.
- Option B: Use manually provided lap distance and ascent values directly.

After lap-level values are determined, the script distributes distance and ascent evenly
across all trackpoints in that lap, then:
- Updates each trackpoint's AltitudeMeters and DistanceMeters (cumulative values).
- Removes Position nodes from updated trackpoints.
- Updates the lap-level DistanceMeters.

Finally, the modified activity is saved as a new file with "_updated" appended to the
original TCX file name.

.NOTES
- Input and output file paths are currently hard-coded in the script.
- The number and order of entries in $ActivityLaps must match the number and order of laps in the TCX activity.
- Existing altitude and distance values are overwritten.
- Position data is removed intentionally for each processed trackpoint.

.EXAMPLE
Run the script directly:
PS> .\Update_TCX_File_2026-05-11.ps1

The script reads the configured TCX file, applies lap updates, and writes
"*_updated.tcx" next to the source file.
#>

#$tcxFile = "C:\Users\Holger\OneDrive - mrhozi\#DailyBuild\GarminConnect\Upload\activity_19083016534.tcx"
#$tcxFile = "C:\Users\HolgerZimmermann\OneDrive - mrhozi\#DailyBuild\GarminConnect\Upload\activity_22938666273.tcx"
#$tcxFile = "C:\Users\Holger\OneDrive - mrhozi\#DailyBuild\GarminConnect\Upload\activity_19083016534.tcx"

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidatePattern('(?i)\.tcx$')]
    [string]$tcxFile
)

if (-not $tcxFile) {
    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select TCX input file"
    $dialog.Filter = "TCX files (*.tcx)|*.tcx"
    $dialog.Multiselect = $false
    $dialog.CheckFileExists = $true
    $dialog.InitialDirectory = (Get-Location).Path

    $dialogResult = $dialog.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.FileName)) {
        throw "No TCX file selected. Script canceled."
    }

    $tcxFile = $dialog.FileName
}

if (-not (Test-Path -LiteralPath $tcxFile -PathType Leaf)) {
    throw "TCX file not found: $tcxFile"
}

if ([System.IO.Path]::GetExtension($tcxFile) -notmatch '^(?i)\.tcx$') {
    throw "Only .tcx files are allowed: $tcxFile"
}

$tcxFile = (Resolve-Path -LiteralPath $tcxFile).Path
$UpdatedtcxFile = $tcxFile.replace(".tcx", "_updated.tcx")

<#
Option A: Calculate Distance and Ascent based on Speed and Incline
Incline in percent, e.g. 10.0 = 10%
Speed in km/h, e.g. 8.0 = 8 km/h

Option B: Use distance and ascent from cardio machine
Distance in meters, e.g. 1000.0 = 1 kilometer
Ascent in meters, e.g. 10.0 = 10 meters
#>

$ActivityLaps = (
    [pscustomobject]@{Lap = "01"; Option = "Stairmaster"; Speed = "9.0"; Incline = "3.0"; Distance = "1100"; Ascent = "0.0"; Description = "Warm Up" },
    [pscustomobject]@{Lap = "02"; Option = "Stairmaster"; Speed = "8.0"; Incline = "12.5"; Distance = "1400"; Ascent = "187"; Description = "Warm Up" },
    [pscustomobject]@{Lap = "03"; Option = "Stairmaster"; Speed = "6.0"; Incline = "15.0"; Distance = "400"; Ascent = "0"; Description = "Exercise" },
    [pscustomobject]@{Lap = "04"; Option = "Stairmaster"; Speed = "5.0"; Incline = "15.0"; Distance = "1350"; Ascent = "182"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "05"; Option = "Stairmaster"; Speed = "6.0"; Incline = "15.0"; Distance = "400"; Ascent = "0.0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "06"; Option = "Stairmaster"; Speed = "5.0"; Incline = "15.0"; Distance = "1450.0"; Ascent = "190.0"; Description = "Einheit 3" },
    [pscustomobject]@{Lap = "07"; Option = "Stairmaster"; Speed = "6.0"; Incline = "15.0"; Distance = "200"; Ascent = "0"; Description = "Einheit 3" },
    [pscustomobject]@{Lap = "08"; Option = "Stairmaster"; Speed = "5.5"; Incline = "15.0"; Distance = "1000"; Ascent = "80"; Description = "Einheit 4" },
    [pscustomobject]@{Lap = "09"; Option = "Stairmaster"; Speed = "6.0"; Incline = "15.0"; Distance = "145"; Ascent = "0"; Description = "Einheit 4" },
    [pscustomobject]@{Lap = "10"; Option = "Stairmaster"; Speed = "5.0"; Incline = "15.0"; Distance = "800"; Ascent = "0"; Description = "Einheit 5" },
    [pscustomobject]@{Lap = "11"; Option = "Treadmill"; Speed = "6.0"; Incline = "15.0"; Distance = "1100"; Ascent = "227"; Description = "Einheit 5" },
    [pscustomobject]@{Lap = "12"; Option = "Treadmill"; Speed = "5.0"; Incline = "15.0"; Distance = "900"; Ascent = "185"; Description = "Einheit 6" },
    [pscustomobject]@{Lap = "13"; Option = "Treadmill"; Speed = "6.0"; Incline = "15.0"; Distance = "650"; Ascent = "0"; Description = "Cool Down" },
    [pscustomobject]@{Lap = "14"; Option = "Treadmill"; Speed = "5.0"; Incline = "15.0"; Distance = "1000.0"; Ascent = "-44.0"; Description = "Cool Down" },
    [pscustomobject]@{Lap = "15"; Option = "Treadmill"; Speed = "6.0"; Incline = "15.0"; Distance = "1000.0"; Ascent = "-6"; Description = "Lap 15" },
    [pscustomobject]@{Lap = "16"; Option = "Treadmill"; Speed = "4.5"; Incline = "15.0"; Distance = "640.0"; Ascent = "-12"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "17"; Option = "Treadmill"; Speed = "5.7"; Incline = "15.0"; Distance = "1300.0"; Ascent = "350"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "18"; Option = "Treadmill"; Speed = "3.0"; Incline = "3.0"; Distance = "140.0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "19"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "1200.0"; Ascent = "318"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "20"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "10"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "21"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "25"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "22"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "23"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "270.0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "24"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "25"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "26"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "27"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "28"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "29"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" },
    [pscustomobject]@{Lap = "30"; Option = "Stairmaster"; Speed = "8.0"; Incline = "8.0"; Distance = "0"; Ascent = "0"; Description = "Einheit 1" }
)

function Edit-ActivityLapsInGrid {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$InputLaps,
        [object[]]$LapNodes,
        [int]$NumberOfLaps = 30
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Edit Activity Laps | Option A: Calculate Distance/Ascent from Speed/Incline (Treadmill) | Option B: Use provided Distance/Ascent values (Stairmaster)"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size(1100, 700)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $grid.AutoGenerateColumns = $false
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    $grid.add_DataError({ param($sender, $e) $e.ThrowException = $false })

    $dataTable = New-Object System.Data.DataTable
    foreach ($columnName in @("Lap", "TotalTimeSeconds", "Option", "Speed", "Incline", "Distance", "Ascent", "Description")) {
        [void]$dataTable.Columns.Add($columnName, [string])
    }

    $counter = 0
    foreach ($lap in $InputLaps) {
        $row = $dataTable.NewRow()
        $row["Lap"] = [string]$lap.Lap
        $lapDurationSeconds = 0.0
        if ($LapNodes -and $counter -lt $LapNodes.Count) {
            $rawTotalTimeSeconds = [string]$LapNodes[$counter].TotalTimeSeconds
            if (-not [double]::TryParse($rawTotalTimeSeconds, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lapDurationSeconds)) {
                [void][double]::TryParse($rawTotalTimeSeconds, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$lapDurationSeconds)
            }
        }
        $row["TotalTimeSeconds"] = [TimeSpan]::FromSeconds($lapDurationSeconds).ToString("hh\:mm\:ss")
        $optionValue = ([string]$lap.Option)
        if ($optionValue -notin @("Treadmill", "Stairmaster")) {
            $optionValue = "Stairmaster"
        }
        $row["Option"] = $optionValue
        $row["Description"] = [string]$lap.Description
        $row["Speed"] = [string]$lap.Speed
        $row["Incline"] = [string]$lap.Incline
        $row["Distance"] = [string]$lap.Distance
        $row["Ascent"] = [string]$lap.Ascent

        [void]$dataTable.Rows.Add($row)
        $counter++

        If ($counter -ge $NumberOfLaps) {
            break
        }
    }

    $grid.Columns.Clear()

    $lapColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $lapColumn.Name = "Lap"
    $lapColumn.HeaderText = "Lap"
    $lapColumn.DataPropertyName = "Lap"
    [void]$grid.Columns.Add($lapColumn)

    $timeColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $timeColumn.Name = "TotalTimeSeconds"
    $timeColumn.HeaderText = "TotalTimeSeconds"
    $timeColumn.DataPropertyName = "TotalTimeSeconds"
    $timeColumn.ReadOnly = $true
    [void]$grid.Columns.Add($timeColumn)

    $descriptionColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $descriptionColumn.Name = "Description"
    $descriptionColumn.HeaderText = "Description"
    $descriptionColumn.DataPropertyName = "Description"
    [void]$descriptionColumn.Items.Add("Warm Up")
    [void]$descriptionColumn.Items.Add("Hike")
    [void]$descriptionColumn.Items.Add("Run")
    [void]$descriptionColumn.Items.Add("Pause")
    [void]$descriptionColumn.Items.Add("Cool Down")
    [void]$grid.Columns.Add($descriptionColumn)

    $optionColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $optionColumn.Name = "Option"
    $optionColumn.HeaderText = "Option"
    $optionColumn.DataPropertyName = "Option"
    [void]$optionColumn.Items.Add("Treadmill")
    [void]$optionColumn.Items.Add("Stairmaster")
    [void]$grid.Columns.Add($optionColumn)


    foreach ($columnName in @("Speed", "Incline", "Distance", "Ascent")) {
        $textColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $textColumn.Name = $columnName
        $textColumn.HeaderText = $columnName
        $textColumn.DataPropertyName = $columnName
        [void]$grid.Columns.Add($textColumn)
    }

    $grid.DataSource = $dataTable

    $activeColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
    $inactiveColor = [System.Drawing.Color]::FromArgb(242, 242, 242)

    $applyRowStyle = {
        param($row)

        if ($null -eq $row -or $row.IsNewRow) {
            return
        }

        $option = [string]$row.Cells["Option"].Value

        $speedCell = $row.Cells["Speed"]
        $inclineCell = $row.Cells["Incline"]
        $distanceCell = $row.Cells["Distance"]
        $ascentCell = $row.Cells["Ascent"]

        if ($option -eq "Treadmill") {
            $speedCell.Style.BackColor = $activeColor
            $inclineCell.Style.BackColor = $activeColor
            $distanceCell.Style.BackColor = $inactiveColor
            $ascentCell.Style.BackColor = $inactiveColor

            $speedCell.ReadOnly = $false
            $inclineCell.ReadOnly = $false
            $distanceCell.ReadOnly = $true
            $ascentCell.ReadOnly = $true
        }
        else {
            $speedCell.Style.BackColor = $inactiveColor
            $inclineCell.Style.BackColor = $inactiveColor
            $distanceCell.Style.BackColor = $activeColor
            $ascentCell.Style.BackColor = $activeColor

            $speedCell.ReadOnly = $true
            $inclineCell.ReadOnly = $true
            $distanceCell.ReadOnly = $false
            $ascentCell.ReadOnly = $false
        }
    }

    $grid.add_DataBindingComplete({
        param($sender, $e)
        foreach ($row in $sender.Rows) {
            & $applyRowStyle $row
        }
    })

    $grid.add_CellValueChanged({
        param($sender, $e)
        if ($e.RowIndex -lt 0) {
            return
        }

        if ($sender.Columns[$e.ColumnIndex].Name -eq "Option") {
            & $applyRowStyle $sender.Rows[$e.RowIndex]
        }
    })

    $grid.add_CurrentCellDirtyStateChanged({
        param($sender, $e)
        if ($sender.IsCurrentCellDirty -and $sender.CurrentCell -and $sender.CurrentCell.OwningColumn.Name -eq "Option") {
            $sender.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })

    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $buttonPanel.Height = 50

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Width = 120
    $okButton.Height = 30
    $okButton.Left = 10
    $okButton.Top = 10
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Width = 120
    $cancelButton.Height = 30
    $cancelButton.Left = 140
    $cancelButton.Top = 10
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    [void]$buttonPanel.Controls.Add($okButton)
    [void]$buttonPanel.Controls.Add($cancelButton)

    [void]$form.Controls.Add($grid)
    [void]$form.Controls.Add($buttonPanel)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $result = @()
    foreach ($row in $dataTable.Rows) {
        $result += [pscustomobject]@{
            Lap = [string]$row.Lap
            TotalTimeSeconds = [string]$row.TotalTimeSeconds
            Option = [string]$row.Option
            Speed = [string]$row.Speed
            Incline = [string]$row.Incline
            Distance = [string]$row.Distance
            Ascent = [string]$row.Ascent
            Description = [string]$row.Description
        }
    }

    return $result
}

function Convert-KmhToPace {
    param (
        [double]$SpeedKmh
    )
    if ($SpeedKmh -le 0) {
        throw "Speed in km/h must be greater than 0"
    }
    
    # Minutes per kilometer
    $minutesPerKm = 60 / $SpeedKmh

    # Calculate whole minutes and remaining seconds
    $minutes = [math]::Floor($minutesPerKm)
    $seconds = [math]::Round(($minutesPerKm - $minutes) * 60)

    # Format result
    return "{0} min {1} sec" -f $minutes, $seconds
}

function Get-DistanceInMeters {
    param (
        [float]$SpeedKmh,     # Speed in km/h
        [float]$TimeSeconds   # Time in seconds
    )
    
    # Convert km/h to m/s
    $speedMs = $SpeedKmh * 1000 / 3600

    # Calculate distance in meters
    $distanceMeters = $speedMs * $TimeSeconds

    # Return distance in meters
    return $distanceMeters
}

function Get-HeightGain {
    param (
        [float]$DistanceMeters,  # Horizontal distance in meters
        [float]$SlopePercentage  # Incline in percent
    )
    
    # Convert incline to decimal (percentage / 100)
    $slopeDecimal = $SlopePercentage / 100

    # Calculate elevation gain
    $heightGainMeters = $DistanceMeters * $slopeDecimal

    # Return result
    return $heightGainMeters
}

function Get-StairMasterMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$InclineAngle,

        [Parameter(Mandatory)]
        [double]$ElevationGain,

        [Parameter()]
        [double]$DurationMinutes = 30
    )

    $angleRad = $InclineAngle * [Math]::PI / 180

    $horizontalDistance = $ElevationGain / [Math]::Tan($angleRad)
    $totalDistance = $ElevationGain / [Math]::Sin($angleRad)
    $averageGrade = ($ElevationGain / $horizontalDistance) * 100
    $verticalSpeed = ($ElevationGain / $DurationMinutes) * 60

    [PSCustomObject]@{
        InclineAngle_Degrees      = [Math]::Round($InclineAngle, 2)
        ElevationGain_Meters      = [Math]::Round($ElevationGain, 2)
        Duration_Minutes          = [Math]::Round($DurationMinutes, 2)
        HorizontalDistance_Meters = [Math]::Round($horizontalDistance, 2)
        TotalDistance_Meters      = [Math]::Round($totalDistance, 2)
        AverageGrade_Percent      = [Math]::Round($averageGrade, 2)
        VerticalSpeed_m_per_h     = [Math]::Round($verticalSpeed, 2)
    }
}



# Check if the file exists
if (-not (Test-Path $tcxFile)) {
    Write-Host "File not found: $tcxFile" -ForegroundColor Red
    exit
}

# load TCX-file
[xml]$tcx = Get-Content $tcxFile

# number of Laps
$NoLaps = ($tcx.TrainingCenterDatabase.Activities.Activity.Lap).count
Write-host "Number of Laps: $NoLaps" -ForegroundColor Green

$allLaps = $tcx.TrainingCenterDatabase.Activities.Activity.Lap

$allLaps | Select-Object TotalTimeSeconds, DistanceMeters,Intensity |  Format-Table

$editedLaps = Edit-ActivityLapsInGrid -InputLaps $ActivityLaps -LapNodes $allLaps -NumberOfLaps $NoLaps

if ($null -eq $editedLaps) {
    Write-Host "Canceled by user. No TCX changes were written." -ForegroundColor Yellow
    exit
}

$ActivityLaps = $editedLaps

if ($ActivityLaps.Count -ne $NoLaps) {
    Write-Host "ActivityLaps count ($($ActivityLaps.Count)) does not match TCX lap count ($NoLaps)." -ForegroundColor Red
    exit
}

$script:i = 1
$allLaps | 
Select-Object @{Name='Lab';Expression={$script:i; $script:i++}}, StartTime, TotalTimeSeconds, DistanceMeters | Format-Table

[double]$startAltitude = 0
[double]$Distance = 625.0
[double]$StartDistance = 0

$i = 0

foreach ($Lap in $allLaps) {
    If ($ActivityLaps[$i].Option -eq "Treadmill") {
    $ActivityLaps[$i].Distance = Get-DistanceInMeters -SpeedKmh $ActivityLaps[$i].Speed -TimeSeconds $Lap.TotalTimeSeconds
    $ActivityLaps[$i].Ascent   = Get-HeightGain -DistanceMeters $ActivityLaps[$i].Distance -SlopePercentage $ActivityLaps[$i].Incline
    }
   $i += 1
}


$ActivityLaps | Format-Table

pause

$i = 0
$previousCumulativeAltitude = 0

foreach ($Lap in $allLaps) {

    [double]$Distance = 0.0
    [double]$Ascent = 0.0
    [double]$CumulativeAltitude = 0.0
    [double]$CumulativeDistance = 0.0
    
    $NoTrackPoints = ($Lap.Track.Trackpoint).count
    $Ascent = $ActivityLaps[$i].Ascent / $NoTrackPoints
    $Ascent = [math]::Round($Ascent, 3)

    $Distance = $ActivityLaps[$i].Distance / $NoTrackPoints
    $Distance = [math]::Round($Distance, 3)

    $lab = $i +1 
    
    write-host "[>] Updating Lap $lab`/$NoLaps  | $($Lap.StartTime) with '$NoTrackPoints' TrackPoints ... " -ForegroundColor Yellow 

    $CumulativeAltitude = $startAltitude
    $CumulativeDistance = $StartDistance 
    
    foreach ($tp in $Lap.track.trackpoint) {
        
        if ($tp.AltitudeMeters -and $tp.AltitudeMeters -match '^\d+(\.\d+)?$') {
            
            $CumulativeAltitude += $Ascent    
            $tp.AltitudeMeters = $CumulativeAltitude.ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
        
            $CumulativeDistance += $Distance
            $tp.DistanceMeters = $CumulativeDistance.ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
        
            $pos = $tp.Position
            if ($null -ne $pos) {
                $tp.RemoveChild($pos) | Out-Null
            }
        }
    }

    $temp = $ActivityLaps[$i].Distance
    $Lap.DistanceMeters =  ([double]$temp).ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
  
    $startAltitude = $CumulativeAltitude
    $StartDistance = $CumulativeDistance


    Write-Host " ... done added $([int]$Lap.DistanceMeters) meters and $($ActivityLaps[$i].Ascent) meters (ascent) [Total elevation: $([int]$CumulativeAltitude) m] to $($Lap.StartTime)" -ForegroundColor Cyan
    
    $i += 1
    $previousCumulativeAltitude = $CumulativeAltitude


}

#$tcx.TrainingCenterDatabase.Activities.Activity.Id = [System.Guid]::NewGuid().ToString()
$tcx.Save($UpdatedtcxFile)

Write-host "[+] Updated TCX file saved as: $UpdatedtcxFile" -ForegroundColor Cyan
Write-host "[!] You can now upload the updated TCX file to Garmin Connect and Strava."