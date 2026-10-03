function Get-GarminActivityList {

    ################################################################################
    #####                                                                      #####
    #####    Returns Garmin Connect activities as array (newest first)         #####
    #####    (/activitylist-service/activities/search/activities)              #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        # Parent types include their sub types (running -> trail_running, treadmill_running, ...); 'all' = no filter
        [string]$ActivityType = 'all',
        [datetime]$StartDate,
        [datetime]$EndDate,
        # Maximum number of activities; 0 = all (within the date range)
        [int]$Last = 0,
        [string]$TokenStore,
        [ValidateRange(1, 200)]
        [int]$PageSize = 100
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $baseQuery = @{}
    if ($ActivityType -and $ActivityType -ne 'all') {
        # Parent types (e.g. running) go to 'activityType', sub types (e.g. yoga, trail_running) to 'activitySubType'
        if (-not $Script:GarminActivityTypes) {
            $Script:GarminActivityTypes = @(Invoke-GarminConnectApi -Path '/activity-service/activity/activityTypes' -TokenStore $TokenStore)
        }
        $typeInfo = $Script:GarminActivityTypes | Where-Object { $_.typeKey -eq $ActivityType } | Select-Object -First 1
        if (-not $typeInfo) {
            throw "Unknown activity type '$ActivityType'. Valid types: $(($Script:GarminActivityTypes.typeKey | Sort-Object) -join ', ')"
        }
        $rootTypeId = ($Script:GarminActivityTypes | Where-Object { $_.typeKey -eq 'all' }).typeId
        if ($typeInfo.parentTypeId -eq $rootTypeId) {
            $baseQuery.activityType = $ActivityType
        }
        else {
            $baseQuery.activitySubType = $ActivityType
        }
    }
    if ($PSBoundParameters.ContainsKey('StartDate')) { $baseQuery.startDate = $StartDate.ToString('yyyy-MM-dd') }
    if ($PSBoundParameters.ContainsKey('EndDate')) { $baseQuery.endDate = $EndDate.ToString('yyyy-MM-dd') }

    # The endpoint is paged; 'start' is 0-based
    $activities = [System.Collections.Generic.List[object]]::new()
    $start = 0
    do {
        $limit = if ($Last -gt 0) { [math]::Min($PageSize, $Last - $activities.Count) } else { $PageSize }
        $query = $baseQuery.Clone()
        $query.start = $start
        $query.limit = $limit
        $page = @(Invoke-GarminConnectApi -Path '/activitylist-service/activities/search/activities' -Query $query -TokenStore $TokenStore)
        foreach ($item in $page) { $activities.Add($item) }
        $start += $page.Count
    } while ($page.Count -eq $limit -and ($Last -le 0 -or $activities.Count -lt $Last))

    $result = $activities.ToArray()
    Write-Log -Message "    >> $($result.Count) activities received (type: $ActivityType)"

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return , $result
}
