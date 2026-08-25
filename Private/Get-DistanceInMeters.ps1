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