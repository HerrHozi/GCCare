
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
