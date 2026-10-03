
function Convert-KmhToPace {
    param (
        [double]$SpeedKmh
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    if ($SpeedKmh -le 0) {
        throw "Speed in km/h must be greater than 0"
    }

    # Seconds per kilometer, rounded first so 59.6 sec does not become "60 sec"
    $totalSeconds = [math]::Round(3600 / $SpeedKmh)

    # Calculate whole minutes and remaining seconds
    $minutes = [math]::Floor($totalSeconds / 60)
    $seconds = $totalSeconds % 60

    # Format result
    $result = "{0} min {1} sec" -f $minutes, $seconds

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
