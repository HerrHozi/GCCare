function Get-DistanceInMeters {
    param (
        [float]$SpeedKmh,     # Speed in km/h
        [float]$TimeSeconds   # Time in seconds
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    # Convert km/h to m/s
    $speedMs = $SpeedKmh * 1000 / 3600

    # Calculate distance in meters
    $distanceMeters = $speedMs * $TimeSeconds

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    # Return distance in meters
    return $distanceMeters
}
