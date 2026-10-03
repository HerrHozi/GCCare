function Get-GarminAvailableBadgeList {

    ################################################################################
    #####                                                                      #####
    #####    Returns all badges the user has not earned yet as array           #####
    #####    (/badge-service/badge/available, earnedByMe = false)              #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [string]$TokenStore
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $badges = @(Invoke-GarminConnectApi -Path '/badge-service/badge/available' -Query @{ showExclusiveBadge = $true } -TokenStore $TokenStore |
            Where-Object { $_.earnedByMe -eq $false })
    Write-Log -Message "    >> $($badges.Count) available badges received"

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return , $badges
}
