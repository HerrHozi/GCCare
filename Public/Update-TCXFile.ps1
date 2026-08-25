<#
.SYNOPSIS
Updates a Garmin TCX activity file by recalculating and rewriting lap and trackpoint data.

.DESCRIPTION
`Update-TCXFile` loads a TCX activity, applies lap configuration values, and writes an updated TCX output file.

The function supports two lap input modes:
- Treadmill: Distance and ascent are calculated from lap duration, speed (km/h), and incline (%).
- Stairmaster (or manual mode): Distance and ascent values are taken directly from configured lap entries.

For each lap, the function:
- Distributes lap distance and ascent across all trackpoints.
- Rewrites `Trackpoint.DistanceMeters` and `Trackpoint.AltitudeMeters` as cumulative values.
- Removes `Trackpoint.Position` nodes.
- Updates lap-level `DistanceMeters`.

An editable lap table is shown through `Edit-ActivityLapsInGrid` before applying updates.
The modified activity is saved as a new file with `_updated` appended to the original file name.

.PARAMETER tcxFile
Path to the input `.tcx` file.
If omitted, a file picker dialog is shown.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior.

.OUTPUTS
None
The function updates and saves a new TCX file on disk and writes status information to the host/output helpers.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`,
  `Edit-ActivityLapsInGrid`, `Get-DistanceInMeters`, `Get-HeightGain`.
- The lap configuration count must match the number of laps in the TCX file.
- Existing altitude, distance, and position values in processed trackpoints are overwritten/removed.
- Output file naming pattern: `<originalName>_updated.tcx`.

.EXAMPLE
Update-TCXFile -tcxFile "C:\Data\workout.tcx"

Loads the specified TCX file, opens lap editing, applies recalculated values, and saves
`workout_updated.tcx` in the same directory.

.EXAMPLE
Update-TCXFile

Opens a file picker dialog, then processes the selected TCX file.
#>
Function Update-TCXFile {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidatePattern('(?i)\.tcx$')]
        [string]$tcxFile,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Updating TCX file with new distance and elevation values ..."

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
            #throw "No TCX file selected. Script canceled."
            Write-Host "  [!] Canceled by user. No tcx file was selected." -ForegroundColor Yellow
            return
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




    # Check if the file exists
    if (-not (Test-Path $tcxFile)) {
        Write-Host "File not found: $tcxFile" -ForegroundColor Red
        exit
    }

    # load TCX-file
    [xml]$tcx = Get-Content $tcxFile

    # number of Laps
    $NoLaps = ($tcx.TrainingCenterDatabase.Activities.Activity.Lap).count

    invoke-output -type Bullet -Message "Number of Laps:" -TextMaker $NoLaps

    $allLaps = $tcx.TrainingCenterDatabase.Activities.Activity.Lap

    $allLaps | Select-Object TotalTimeSeconds, DistanceMeters, Intensity |  Format-Table

    $editedLaps = Edit-ActivityLapsInGrid -InputLaps $ActivityLaps -LapNodes $allLaps -NumberOfLaps $NoLaps

    if ($null -eq $editedLaps) {
        Write-Host "Canceled by user. No TCX changes were written." -ForegroundColor Yellow
        return
    }

    $ActivityLaps = $editedLaps

    if ($ActivityLaps.Count -ne $NoLaps) {
        Write-Host "ActivityLaps count ($($ActivityLaps.Count)) does not match TCX lap count ($NoLaps)." -ForegroundColor Red
        return
    }

    $script:i = 1
    $allLaps | 
    Select-Object @{Name = 'Lab'; Expression = { $script:i; $script:i++ } }, StartTime, TotalTimeSeconds, DistanceMeters | Format-Table

    [double]$startAltitude = 0
    [double]$Distance = 625.0
    [double]$StartDistance = 0

    $i = 0

    foreach ($Lap in $allLaps) {
        If ($ActivityLaps[$i].Option -eq "Treadmill") {
            $ActivityLaps[$i].Distance = Get-DistanceInMeters -SpeedKmh $ActivityLaps[$i].Speed -TimeSeconds $Lap.TotalTimeSeconds
            $ActivityLaps[$i].Ascent = Get-HeightGain -DistanceMeters $ActivityLaps[$i].Distance -SlopePercentage $ActivityLaps[$i].Incline
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

        $lab = $i + 1 
    
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
        $Lap.DistanceMeters = ([double]$temp).ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
  
        $startAltitude = $CumulativeAltitude
        $StartDistance = $CumulativeDistance


        Write-Host " ... done added $([int]$Lap.DistanceMeters) meters and $($ActivityLaps[$i].Ascent) meters (ascent) [Total elevation: $([int]$CumulativeAltitude) m] to $($Lap.StartTime)" -ForegroundColor Cyan
    
        $i += 1
        $previousCumulativeAltitude = $CumulativeAltitude


    }

    #$tcx.TrainingCenterDatabase.Activities.Activity.Id = [System.Guid]::NewGuid().ToString()
    $tcx.Save($UpdatedtcxFile)

    Invoke-output -Type Success -Message "The updated TCX file is now ready to upload to Garmin Connect and Strava."
    Invoke-output -Type Info -Message "Updated TCX file saved as: $UpdatedtcxFile"

    Write-Log -Message "    >> using "
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}