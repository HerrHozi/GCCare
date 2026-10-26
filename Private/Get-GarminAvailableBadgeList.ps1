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

    $Info = Measure-FunctionRuntime -Begin

    $badges = @(Invoke-GarminConnectApi -Path '/badge-service/badge/available' -Query @{ showExclusiveBadge = $true } -TokenStore $TokenStore |
        Where-Object { $_.earnedByMe -eq $false })
    
    Write-Log -Message "    >> $($badges.Count) available badges received"

    Measure-FunctionRuntime -End -Details $Info 

    return $badges
}
