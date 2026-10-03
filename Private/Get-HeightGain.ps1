function Get-HeightGain {
    param (
        [float]$DistanceMeters,  # Horizontal distance in meters
        [float]$SlopePercentage  # Incline in percent
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    # Convert incline to decimal (percentage / 100)
    $slopeDecimal = $SlopePercentage / 100

    # Calculate elevation gain
    $heightGainMeters = $DistanceMeters * $slopeDecimal

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    # Return result
    return $heightGainMeters
}
