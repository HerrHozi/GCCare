function Get-GarminEarnedBadgeList {

    ################################################################################
    #####                                                                      #####
    #####    Returns all badges earned by the user as array                    #####
    #####    (/badge-service/badge/earned)                                     #####
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

    $badges = @(Invoke-GarminConnectApi -Path '/badge-service/badge/earned' -TokenStore $TokenStore)
    Write-Log -Message "    >> $($badges.Count) earned badges received"

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return , $badges
}
