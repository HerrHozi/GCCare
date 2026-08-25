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