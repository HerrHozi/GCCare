<#
.SYNOPSIS
Fetches Garmin Connect activities and summarizes them by year, month, week or activity type.

.DESCRIPTION
`Get-GarminActivity` calls the Garmin Connect API endpoint
`/activitylist-service/activities/search/activities` directly from PowerShell.
Authentication uses the DI OAuth2 token store written by `Get-GarminToken`
(`gctoken.json`). An access token that expires within 15 minutes is refreshed
automatically and saved back.

Without parameters, the last 10 running activities are returned. `-ActivityType`
selects another type (parent types include their sub types, e.g. `running` also returns
`trail_running` and `treadmill_running`; `all` returns every type). With `-StartDate`
and/or `-EndDate`, all activities in the date range are returned; `-Last` limits them.

The activity objects returned by the API are extended with calculated properties in
metric units, or in imperial units with `-Miles`:
- StartTime:     Local start time as [datetime].
- TypeKey:       Activity type key (for example `trail_running`).
- TotalDistance: Distance in km (mi with `-Miles`), rounded to two decimals.
- TotalTime:     Duration as hh:mm:ss.
- AvgPace:       Average pace per km (per mi with `-Miles`).
- AvgSpeed:      Average speed in km/h (mph with `-Miles`).
- ElevGain:      Elevation gain in m (ft with `-Miles`).
- Unit:          'km' or 'mi'.
The console shows these columns by default; all API properties remain available
(`| Select-Object *`).

With `-GroupBy Year`, `Month`, `Week` (ISO 8601) or `ActivityType`, summary objects are
returned instead. The first row always has `Year = 'Total'` (or `TypeKey = 'Total'`).

Summary object properties:
- Year:       'Total' or the four-digit (ISO) year.
- Month/Week: Two-digit month or ISO week (only with `-GroupBy Month` / `Week`).
- TypeKey:    Activity type key (only with `-GroupBy ActivityType`).
- Activities: Number of activities.
- Distance:   Distance in km (mi with `-Miles`).
- Time:       Duration as h:mm:ss.
- ElevGain:   Elevation gain in m (ft with `-Miles`).
- Unit:       'km' or 'mi'.

With `-CustomSelection`, the Where-Object filter and the Select-Object properties are
read from `$env:USERPROFILE\GCCare\Config\GCCare.json` (section
`GarminConnectApi > CustomSelection > Activity > <ActivityType>`, fallback `Default`).
The calculated properties can be used there as well. `-Filter` and `-Property` override
these values for one call, `-SaveCustomSelection` stores them under the activity type
(`Default` for `-ActivityType all`). Together with `-GroupBy`, only the filter is applied
before grouping; the properties are ignored.

.PARAMETER ActivityType
Activity type key, e.g. `running`, `cycling`, `hiking`, `walking`, `swimming`,
`strength_training`, or `all`. Default: `running`. Parent types include their sub types;
sub types like `yoga` or `trail_running` return only that sub type. The valid keys are
read from `/activity-service/activity/activityTypes` (once per session).

.PARAMETER Last
Maximum number of activities (newest first). Default: 10, or all activities in the date
range when `-StartDate` or `-EndDate` is used.

.PARAMETER StartDate
First day of the date range.

.PARAMETER EndDate
Last day of the date range. Default with `-StartDate`: today.

.PARAMETER Miles
Shows distance in miles, pace per mile, speed in mph and elevation in feet.

.PARAMETER GroupBy
Optional summary. Valid values: `Year`, `Month`, `Week`, `ActivityType`.

.PARAMETER CustomSelection
Applies the Where-Object filter and the Select-Object properties stored in `GCCare.json`
for the activity type.

.PARAMETER Filter
Where-Object filter for this call, e.g. `{ $_.TotalDistance -ge 10 }`. Overrides the value
from `GCCare.json` and implies `-CustomSelection`.

.PARAMETER Property
Select-Object properties for this call, e.g. `StartTime, activityName, TotalDistance`.
Overrides the value from `GCCare.json` and implies `-CustomSelection`.

.PARAMETER SaveCustomSelection
Saves `-Filter` and/or `-Property` for the activity type in
`$env:USERPROFILE\GCCare\Config\GCCare.json`. Requires `-Filter` or `-Property`.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `gctoken.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Object[]
Returns the activities, or summary objects when `-GroupBy` is specified.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`,
  `Get-GarminActivityList`, `Get-GCCareCustomSelection`, `Save-GCCareCustomSelection`,
  `Convert-KmhToPace`, `Convert-SecondsToMinutes`.
- Requires a token file created by `Get-GarminToken`.
- The Where-Object value in `GCCare.json` is executed as PowerShell code. Only store
  filters you trust.
- A `Filter` on calculated properties uses the unit of the current call (`-Miles`).

.EXAMPLE
Get-GarminActivity

Returns the last 10 running activities.

.EXAMPLE
Get-GarminActivity -ActivityType all -Last 20 -Miles

Returns the last 20 activities of all types in miles.

.EXAMPLE
Get-GarminActivity -StartDate 2026-01-01 -GroupBy Month | Format-Table

Shows the running activities, distance, time and elevation gain per month of 2026.

.EXAMPLE
Get-GarminActivity -ActivityType all -StartDate 2026-01-01 -GroupBy ActivityType | Format-Table

Shows the activities of 2026 per activity type.

.EXAMPLE
Get-GarminActivity -StartDate 2026-09-01 -EndDate 2026-09-30 -CustomSelection | Format-Table

Returns the running activities of September 2026 with the filter and properties from `GCCare.json`.

.EXAMPLE
Get-GarminActivity -ActivityType cycling -Property StartTime, activityName, TotalDistance, AvgSpeed -SaveCustomSelection

Saves the properties for cycling in `GCCare.json` and returns the last 10 rides with them.
#>
function Get-GarminActivity {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete)
                # All Garmin types once they were loaded in this session, otherwise the common ones
                $keys = if ($Script:GarminActivityTypes) { $Script:GarminActivityTypes.typeKey | Sort-Object } else {
                    'running', 'trail_running', 'treadmill_running', 'cycling', 'walking', 'hiking', 'swimming', 'lap_swimming',
                    'open_water_swimming', 'strength_training', 'fitness_equipment', 'indoor_cardio', 'yoga', 'winter_sports',
                    'multi_sport', 'other', 'all'
                }
                $keys | Where-Object { $_ -like "$wordToComplete*" }
            })]
        [string]$ActivityType = 'running',
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last = 10,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [switch]$Miles,
        [ValidateSet('Year', 'Month', 'Week', 'ActivityType')]
        [string]$GroupBy,
        [switch]$CustomSelection,
        [scriptblock]$Filter,
        [string[]]$Property,
        [switch]$SaveCustomSelection,
        [string]$TokenStore,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    if ($SaveCustomSelection -and -not ($PSBoundParameters.ContainsKey('Filter') -or $PSBoundParameters.ContainsKey('Property'))) {
        throw "-SaveCustomSelection requires -Filter and/or -Property."
    }
    $useCustomSelection = $CustomSelection -or $PSBoundParameters.ContainsKey('Filter') -or $PSBoundParameters.ContainsKey('Property')
    $selectionName = if ($ActivityType -eq 'all') { 'Default' } else { $ActivityType }

    # Units: metric (default) or imperial (-Miles)
    $unit = if ($Miles) { 'mi' } else { 'km' }
    $metersPerUnit = if ($Miles) { 1609.344 } else { 1000.0 }
    $elevationFactor = if ($Miles) { 3.28084 } else { 1.0 }

    function Format-TotalTime([double]$Seconds) {
        $span = [TimeSpan]::FromSeconds($Seconds)
        '{0}:{1:00}:{2:00}' -f [int][math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    }

    function Get-ActivitySummaryRow([System.Collections.Specialized.OrderedDictionary]$Row, $Activities) {
        $Row.Activities = @($Activities).Count
        $Row.Distance = [math]::Round(((@($Activities) | Measure-Object -Property distance -Sum).Sum / $metersPerUnit), 2)
        $Row.Time = Format-TotalTime ((@($Activities) | Measure-Object -Property duration -Sum).Sum)
        $Row.ElevGain = [int][math]::Round(((@($Activities) | Measure-Object -Property elevationGain -Sum).Sum * $elevationFactor), 0)
        $Row.Unit = $unit
        [pscustomobject]$Row
    }

    # Fetch: the last X activities, or all activities in the date range
    $listParams = @{ ActivityType = $ActivityType; TokenStore = $TokenStore }
    $hasDateRange = $PSBoundParameters.ContainsKey('StartDate') -or $PSBoundParameters.ContainsKey('EndDate')
    if ($hasDateRange) {
        $listParams.StartDate = if ($PSBoundParameters.ContainsKey('StartDate')) { $StartDate } else { [datetime]'2000-01-01' }
        $listParams.EndDate = if ($PSBoundParameters.ContainsKey('EndDate')) { $EndDate } else { Get-Date }
        if ($PSBoundParameters.ContainsKey('Last')) { $listParams.Last = $Last }
    }
    else {
        $listParams.Last = $Last
    }

    Invoke-Output -Type Header -Message "Fetching Garmin Connect activities ($ActivityType)..."
    $activities = Get-GarminActivityList @listParams

    # Calculated properties; default display = overview columns, all API properties stay available
    $displaySet = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet',
        [string[]]@('StartTime', 'activityName', 'TypeKey', 'TotalDistance', 'TotalTime', 'AvgPace', 'ElevGain', 'Unit'))
    $standardMembers = [System.Management.Automation.PSMemberInfo[]]@($displaySet)

    foreach ($activity in $activities) {
        $speedPerHour = if ($activity.averageSpeed -gt 0) { [double]$activity.averageSpeed * 3600 / $metersPerUnit } else { 0 }
        $activity | Add-Member -Force -NotePropertyMembers ([ordered]@{
                StartTime     = [datetime]::Parse([string]$activity.startTimeLocal, [Globalization.CultureInfo]::InvariantCulture)
                TypeKey       = $activity.activityType.typeKey
                TotalDistance = [math]::Round(([double]$activity.distance / $metersPerUnit), 2)
                TotalTime     = Convert-SecondsToMinutes -Seconds ([string][double]$activity.duration)
                AvgPace       = if ($speedPerHour -gt 0) { Convert-KmhToPace -SpeedKmh $speedPerHour } else { $null }
                AvgSpeed      = [math]::Round($speedPerHour, 2)
                ElevGain      = [int][math]::Round(([double]$activity.elevationGain * $elevationFactor), 0)
                Unit          = $unit
            })
        $activity | Add-Member -Force -MemberType MemberSet -Name PSStandardMembers -Value $standardMembers
    }

    # Console summary
    Write-Host ""
    $totalRow = Get-ActivitySummaryRow ([ordered]@{}) $activities
    Invoke-Output -Type Bullet -Message "Activities:    " -TextMaker $totalRow.Activities -NoExtraLines
    Invoke-Output -Type Bullet -Message "Distance:      " -TextMaker "$($totalRow.Distance) $unit" -NoExtraLines
    Invoke-Output -Type Bullet -Message "Time:          " -TextMaker $totalRow.Time -NoExtraLines
    Invoke-Output -Type Bullet -Message "Elevation Gain:" -TextMaker "$($totalRow.ElevGain) $(if ($Miles) { 'ft' } else { 'm' })"

    # Custom selection: GCCare.json < -Filter / -Property
    $selectProperties = @()
    if ($useCustomSelection) {
        if ($SaveCustomSelection) {
            $saveParams = @{ Section = 'Activity'; Name = $selectionName }
            if ($PSBoundParameters.ContainsKey('Filter')) { $saveParams.Filter = $Filter }
            if ($PSBoundParameters.ContainsKey('Property')) { $saveParams.Property = $Property }
            Save-GCCareCustomSelection @saveParams
        }

        $selection = Get-GCCareCustomSelection -Section 'Activity' -Name $selectionName -DefaultName 'Default'
        $whereFilter = if ($PSBoundParameters.ContainsKey('Filter')) { $Filter } else { $selection.Filter }
        $selectProperties = if ($PSBoundParameters.ContainsKey('Property')) { @($Property) } else { @($selection.Property) }

        if ($whereFilter) {
            $activities = @($activities | Where-Object -FilterScript $whereFilter)
            Write-Log -Message "    >> Filter {$whereFilter}: $($activities.Count) activities left"
        }
    }

    $result = $activities

    if ($GroupBy) {
        $summary = @()
        if ($GroupBy -eq 'ActivityType') {
            $summary += Get-ActivitySummaryRow ([ordered]@{ TypeKey = 'Total' }) $activities
            foreach ($group in ($activities | Group-Object -Property TypeKey | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)) {
                $summary += Get-ActivitySummaryRow ([ordered]@{ TypeKey = $group.Name }) $group.Group
            }
        }
        else {
            # Group keys 'yyyy', 'yyyy-MM' or 'yyyy-Www' (ISO week) sort chronologically as plain strings
            $keyScript = switch ($GroupBy) {
                'Year' { { $_.StartTime.ToString('yyyy') } }
                'Month' { { $_.StartTime.ToString('yyyy-MM') } }
                'Week' { { '{0}-W{1:00}' -f [Globalization.ISOWeek]::GetYear($_.StartTime), [Globalization.ISOWeek]::GetWeekOfYear($_.StartTime) } }
            }

            $totalRow = [ordered]@{ Year = 'Total' }
            if ($GroupBy -eq 'Month') { $totalRow.Month = '' }
            if ($GroupBy -eq 'Week') { $totalRow.Week = '' }
            $summary += Get-ActivitySummaryRow $totalRow $activities

            foreach ($group in ($activities | Group-Object -Property $keyScript | Sort-Object -Property Name)) {
                $row = [ordered]@{ Year = $group.Name.Substring(0, 4) }
                if ($GroupBy -eq 'Month') { $row.Month = $group.Name.Substring(5, 2) }
                if ($GroupBy -eq 'Week') { $row.Week = $group.Name.Substring(6, 2) }
                $summary += Get-ActivitySummaryRow $row $group.Group
            }
        }
        $result = $summary
    }
    elseif ($selectProperties.Count -gt 0) {
        $result = $activities | Select-Object -Property $selectProperties
    }

    Invoke-Output -Type Success -Message "Garmin Connect activities fetched successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
