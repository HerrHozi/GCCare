<#
.SYNOPSIS
Analyzes a Garmin TCX activity file and returns lap-based performance metrics.

.DESCRIPTION
`Invoke-TCXFileAnalysis` reads a TCX activity file, evaluates each lap, and returns
a structured list of metrics including distance, lap time, moving time, non-moving time,
ascent, descent, pace, and heart-rate values.

If no file path is provided, a file picker dialog is shown to select a `.tcx` file.
The function validates the selected input file, parses activity/lap data, calculates
movement-related metrics from trackpoints, and summarizes cumulative totals across laps.

.PARAMETER tcxFile
Path to the input `.tcx` file.
If omitted, an OpenFileDialog is shown.

.PARAMETER EnableLogging
Optional switch to enable logging behavior (if supported by the module logging functions).

.OUTPUTS
System.Collections.Generic.List[object]
Returns one object per lap with calculated and cumulative activity metrics.

.NOTES
- Requires helper functions available in the module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Convert-SecondsToMinutes`, `Get-RunTime`.
- Moving time is determined using speed and distance delta thresholds between trackpoints.
- Elevation gain/loss is calculated only during moving segments.
- Input file must have `.tcx` extension.

.EXAMPLE
Invoke-TCXFileAnalysis -tcxFile "C:\Data\activity.tcx"

Analyzes the provided activity file and returns lap metrics.

.EXAMPLE
Invoke-TCXFileAnalysis

Opens a file picker to select a TCX file, then analyzes it.
#>
Function Invoke-TCXFileAnalysis {

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

    Invoke-Output -Type Header -Message "Analyzing TCX file ..."

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



    # Check if the file exists
    if (-not (Test-Path $tcxFile)) {
        Write-Host "File not found: $tcxFile" -ForegroundColor Red
        exit
    }

    # load TCX-file
    [xml]$tcx = Get-Content $tcxFile

    # number of Laps
    $NoLaps = ($tcx.TrainingCenterDatabase.Activities.Activity.Lap).count
    $Sport = $tcx.TrainingCenterDatabase.Activities.Activity.Sport
    $id = $tcx.TrainingCenterDatabase.Activities.Activity.id
    $device = $tcx.TrainingCenterDatabase.Activities.Activity.Creator.Name  
    $deviceId = $tcx.TrainingCenterDatabase.Activities.Activity.Creator.UnitId        
    
    invoke-output -type Bullet -Message "Device:         " -TextMaker "$device ($deviceId)"
    invoke-output -type Bullet -Message "Activity ID:    " -TextMaker $id
    invoke-output -type Bullet -Message "Sport:          " -TextMaker $Sport
    invoke-output -type Bullet -Message "Number of Laps: " -TextMaker $NoLaps

    $allLaps = $tcx.TrainingCenterDatabase.Activities.Activity.Lap

    function Format-PaceMinPerKm {
        param(
            [Parameter(Mandatory)]
            [double]$Seconds,
            [Parameter(Mandatory)]
            [double]$DistanceMeters
        )

        if ($DistanceMeters -le 0 -or $Seconds -lt 0) {
            return $null
        }

        [double]$paceSecondsPerKm = $Seconds / ($DistanceMeters / 1000.0)
        return [TimeSpan]::FromSeconds($paceSecondsPerKm).ToString("mm\:ss")
    }



    function Get-LapMovementMetrics {
        param(
            [Parameter(Mandatory)]
            $LapNode
        )

        $trackpoints = @($LapNode.Track.Trackpoint)
        if ($trackpoints.Count -lt 2) {
            return [PSCustomObject]@{
                TotalAscentMeters  = 0.0
                TotalDescentMeters = 0.0
                MovingTimeSeconds  = 0.0
            }
        }

        [double]$minimumMovingSpeedMps = 0.6
        [double]$minimumFallbackDistanceDeltaMeters = 0.5
        [double]$minimumElevationDeltaMeters = 0.1
        [double]$maximumTrackpointGapSeconds = 10.0

        [double]$movingSeconds = 0.0
        [double]$ascent = 0.0
        [double]$descent = 0.0

        [double]$previousAltitude = 0.0
        [double]$previousDistance = 0.0
        [datetime]$previousTime = [datetime]::MinValue
        [double]$previousSpeed = 0.0
        [bool]$hasPreviousAltitude = $false
        [bool]$hasPreviousDistance = $false
        [bool]$hasPreviousTime = $false
        [bool]$hasPreviousSpeed = $false

        foreach ($tp in $trackpoints) {
            [double]$currentAltitude = 0.0
            [double]$currentDistance = 0.0
            [datetime]$currentTime = [datetime]::MinValue
            [double]$currentSpeed = 0.0

            $hasCurrentAltitude = [double]::TryParse(
                [string]$tp.AltitudeMeters,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$currentAltitude
            )

            if (-not $hasCurrentAltitude) {
                $hasCurrentAltitude = [double]::TryParse(
                    [string]$tp.AltitudeMeters,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::CurrentCulture,
                    [ref]$currentAltitude
                )
            }

            $hasCurrentDistance = [double]::TryParse(
                [string]$tp.DistanceMeters,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$currentDistance
            )

            if (-not $hasCurrentDistance) {
                $hasCurrentDistance = [double]::TryParse(
                    [string]$tp.DistanceMeters,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::CurrentCulture,
                    [ref]$currentDistance
                )
            }

            $hasCurrentTime = [datetime]::TryParse(
                [string]$tp.Time,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$currentTime
            )

            $hasCurrentSpeed = [double]::TryParse(
                [string]$tp.Extensions.TPX.Speed,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$currentSpeed
            )

            if (-not $hasCurrentSpeed) {
                $hasCurrentSpeed = [double]::TryParse(
                    [string]$tp.Extensions.TPX.Speed,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::CurrentCulture,
                    [ref]$currentSpeed
                )
            }

            if ($hasPreviousTime -and $hasCurrentTime -and $hasPreviousDistance -and $hasCurrentDistance) {
                $timeDelta = ($currentTime - $previousTime).TotalSeconds
                $distanceDelta = $currentDistance - $previousDistance

                if ($timeDelta -gt 0 -and $timeDelta -le $maximumTrackpointGapSeconds) {
                    $countsAsMoving = $false

                    if ($hasPreviousSpeed -and $hasCurrentSpeed) {
                        if ($previousSpeed -ge $minimumMovingSpeedMps -or $currentSpeed -ge $minimumMovingSpeedMps) {
                            $countsAsMoving = $true
                        }
                    }
                    elseif ($distanceDelta -ge $minimumFallbackDistanceDeltaMeters) {
                        $countsAsMoving = $true
                    }

                    if ($countsAsMoving) {
                        $movingSeconds += $timeDelta

                        if ($hasPreviousAltitude -and $hasCurrentAltitude) {
                            $altitudeDelta = $currentAltitude - $previousAltitude
                            if ($altitudeDelta -ge $minimumElevationDeltaMeters) {
                                $ascent += $altitudeDelta
                            }
                            elseif ($altitudeDelta -le (-1.0 * $minimumElevationDeltaMeters)) {
                                $descent += [math]::Abs($altitudeDelta)
                            }
                        }
                    }
                }
            }

            if ($hasCurrentAltitude) {
                $previousAltitude = $currentAltitude
                $hasPreviousAltitude = $true
            }

            if ($hasCurrentDistance) {
                $previousDistance = $currentDistance
                $hasPreviousDistance = $true
            }

            if ($hasCurrentTime) {
                $previousTime = $currentTime
                $hasPreviousTime = $true
            }

            if ($hasCurrentSpeed) {
                $previousSpeed = $currentSpeed
                $hasPreviousSpeed = $true
            }
        }

        [double]$lapTotalTimeSeconds = 0.0
        [void][double]::TryParse(
            [string]$LapNode.TotalTimeSeconds,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$lapTotalTimeSeconds
        )

        if ($lapTotalTimeSeconds -gt 0) {
            $movingSeconds = [math]::Min($movingSeconds, $lapTotalTimeSeconds)
        }

        return [PSCustomObject]@{
            TotalAscentMeters  = [math]::Round($ascent, 0)
            TotalDescentMeters = [math]::Round($descent, 0)
            MovingTimeSeconds  = [math]::Round($movingSeconds, 0)
        }
    }



    $i = 0
    $Results = [System.Collections.Generic.List[object]]::new()
    [double]$totalDistanceMeters = 0.0
    [double]$totalTimeSeconds = 0.0
    [double]$totalMovingTimeSeconds = 0.0
    [double]$totalAscentMeters = 0.0
    [double]$totalDescentMeters = 0.0
    [double]$averageHeartRateSum = 0.0
    [int]$averageHeartRateCount = 0
    [double]$maximumHeartRate = 0.0
    
    foreach ($Lap in $allLaps) {

        $movementMetrics = Get-LapMovementMetrics -LapNode $Lap

        [double]$lapDistanceMeters = 0.0
        [void][double]::TryParse(
            [string]$Lap.DistanceMeters,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$lapDistanceMeters
        )

        [double]$lapTotalTimeSeconds = 0.0
        [void][double]::TryParse(
            [string]$Lap.TotalTimeSeconds,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$lapTotalTimeSeconds
        )


        $totalDistanceMeters += $lapDistanceMeters
        $totalTimeSeconds += $lapTotalTimeSeconds
        $totalMovingTimeSeconds += [double]$movementMetrics.MovingTimeSeconds
        $totalAscentMeters += [double]$movementMetrics.TotalAscentMeters
        $totalDescentMeters += [double]$movementMetrics.TotalDescentMeters

        [double]$lapAverageHeartRate = 0.0
        if ([double]::TryParse([string]$Lap.AverageHeartRateBpm.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lapAverageHeartRate) -or
            [double]::TryParse([string]$Lap.AverageHeartRateBpm.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$lapAverageHeartRate)) {
            $averageHeartRateSum += $lapAverageHeartRate
            $averageHeartRateCount += 1
        }

        [double]$lapMaximumHeartRate = 0.0
        if ([double]::TryParse([string]$Lap.MaximumHeartRateBpm.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lapMaximumHeartRate) -or
            [double]::TryParse([string]$Lap.MaximumHeartRateBpm.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$lapMaximumHeartRate)) {
            if ($lapMaximumHeartRate -gt $maximumHeartRate) {
                $maximumHeartRate = $lapMaximumHeartRate
            }
        }

        $Results.Add(
            [PSCustomObject]@{
                Lap                 = $i + 1
                LapTime             = Convert-SecondsToMinutes -Seconds $Lap.TotalTimeSeconds
                DistanceKm          = [math]::Round(($lapDistanceMeters / 1000.0), 2)
                MovingTime          = Convert-SecondsToMinutes -Seconds $movementMetrics.MovingTimeSeconds
                NonMovingTime       = Convert-SecondsToMinutes -Seconds ($lapTotalTimeSeconds - $movementMetrics.MovingTimeSeconds)
                AscentMeters        = $movementMetrics.TotalAscentMeters
                DescentMeters       = $movementMetrics.TotalDescentMeters
                AveragePaceMinKm    = Format-PaceMinPerKm -Seconds $lapTotalTimeSeconds -DistanceMeters $lapDistanceMeters
                MovingPaceMinKm     = Format-PaceMinPerKm -Seconds $movementMetrics.MovingTimeSeconds -DistanceMeters $lapDistanceMeters
                AverageHeartRateBpm = $Lap.AverageHeartRateBpm.Value
                MaximumHeartRateBpm = $Lap.MaximumHeartRateBpm.Value
                AvgSpeed            = $Lap.Extensions.lx.AvgSpeed
                StartTime           = $Lap.StartTime
                DistanceMeter       = $Lap.DistanceMeters
                TotalDistance       = [math]::Round($totalDistanceMeters / 1000.0, 2)
                TotalTime           = Convert-SecondsToMinutes -Seconds $totalTimeSeconds
                TotalAscentMeters   = [math]::Round($totalAscentMeters, 0)
                TotalDescentMeters  = [math]::Round($totalDescentMeters, 0)
            }
        )
        $i += 1
    }
    <#
    $Results.Add(
        [PSCustomObject]@{
            LapNumber           = 'Total'
            TotalTime           = Convert-SecondsToMinutes -Seconds $totalTimeSeconds
            DistanceKm          = [math]::Round(($totalDistanceMeters / 1000.0), 2)
            MovingTime          = Convert-SecondsToMinutes -Seconds $totalMovingTimeSeconds
            TotalAscentMeters   = [math]::Round($totalAscentMeters, 0)
            TotalDescentMeters  = [math]::Round($totalDescentMeters, 0)
            AveragePaceMinKm    = Format-PaceMinPerKm -Seconds $totalTimeSeconds -DistanceMeters $totalDistanceMeters
            MovingPaceMinKm     = Format-PaceMinPerKm -Seconds $totalMovingTimeSeconds -DistanceMeters $totalDistanceMeters
            AverageHeartRateBpm = if ($averageHeartRateCount -gt 0) { [math]::Round(($averageHeartRateSum / $averageHeartRateCount), 0) } else { $null }
            MaximumHeartRateBpm = if ($maximumHeartRate -gt 0) { [math]::Round($maximumHeartRate, 0) } else { $null }
            AvgSpeed            = $null
            StartTime           = $null
            DistanceMeter       = [math]::Round($totalDistanceMeters, 2)
            TotalDistanceMeter  = [math]::Round($totalDistanceMeters, 2)
        }
    )
#>

    #$Results | Format-Table | Out-Host

    Invoke-output -Type Success -Message "TCX file analysis completed."

    Write-Log -Message "    >> using "
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $Results

}





