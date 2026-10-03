function Get-GarminNonCompletedBadgeList {

    ################################################################################
    #####                                                                      #####
    #####    Returns all joined, not yet completed badge challenges as array   #####
    #####    (/badgechallenge-service/badgeChallenge/non-completed)            #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [string]$TokenStore,
        [ValidateRange(1, 100)]
        [int]$PageSize = 100
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    # The endpoint is paged; 'start' is 1-based (start = 0 returns HTTP 400)
    $challenges = [System.Collections.Generic.List[object]]::new()
    $start = 1
    do {
        $page = @(Invoke-GarminConnectApi -Path '/badgechallenge-service/badgeChallenge/non-completed' `
                -Query @{ showExclusiveBadge = $true; start = $start; limit = $PageSize } -TokenStore $TokenStore)
        foreach ($item in $page) { $challenges.Add($item) }
        $start += $PageSize
    } while ($page.Count -eq $PageSize)

    $badges = @($challenges | Where-Object { $null -eq $_.badgeEarnedDate })
    Write-Log -Message "    >> $($badges.Count) non-completed badge challenges received"

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return , $badges
}
