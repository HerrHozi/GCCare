function Convert-SecondsToMinutes {

    ################################################################################
    #####                                                                      ##### 
    #####    convert seconds to minutes  hh:mm:ss                              #####                                 
    #####                                                                      #####
    ################################################################################

    param(
        [string] $Seconds
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################
    
    $lapDurationSeconds = 0.0

    if (-not [double]::TryParse($Seconds, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lapDurationSeconds)) {
        [void][double]::TryParse($Seconds, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$lapDurationSeconds)
    }

    $minute = [TimeSpan]::FromSeconds($lapDurationSeconds).ToString("hh\:mm\:ss")
    return $minute

    Write-Log -Message "    >> using "
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $true
}