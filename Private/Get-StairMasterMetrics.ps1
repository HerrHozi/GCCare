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