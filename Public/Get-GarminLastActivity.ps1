<#
.SYNOPSIS
Fetches the most recent Garmin Connect activity.

.DESCRIPTION
`Get-GarminLastActivity` calls the Garmin Connect API endpoint
`/activitylist-service/activities/search/activities` directly from PowerShell.
 Authentication uses the DI OAuth2 token store written by `Get-GarminToken`
(`garmin_tokens.json`). An access token that expires within 15 minutes is
refreshed automatically and saved back.

Returns a summary object with these properties:
- Connected:           Always `$true` when the call succeeded.
- ActivityId:          Garmin activity ID.
- ActivityName:        Activity name.
- ActivityType:        Activity type key (for example `running`).
- StartTimeLocal:      Local start time as returned by Garmin.
- DurationSeconds:     Duration in seconds.
- DistanceKm:          Distance in kilometers, rounded to two decimals.
- ElevationGainMeters: Elevation gain in meters.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `garmin_tokens.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER Raw
Optional switch to return the unmodified activity object from the API instead of the summary.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the summary of the last activity, or the raw API object with `-Raw`.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`.
- Requires a token file created by `Get-GarminToken`.

.EXAMPLE
Get-GarminLastActivity

Returns a summary of the most recent Garmin Connect activity.

.EXAMPLE
Get-GarminLastActivity -TokenStore "C:\Temp\.garminconnect"

Fetches the last activity using a custom token store.

.EXAMPLE
Get-GarminLastActivity -Raw

Returns the complete activity object as delivered by the API.
#>
function Get-GarminLastActivity {

    [CmdletBinding()]
    param(
        [string]$TokenStore,
        [switch]$Raw,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Fetching last Garmin Connect activity..."

    $activities = @(Invoke-GarminConnectApi -Path '/activitylist-service/activities/search/activities' `
            -Query @{ start = 0; limit = 1 } -TokenStore $TokenStore)
    $activity = $activities | Select-Object -First 1

    if ($null -eq $activity) {
        throw 'Connected, but no activity was returned by Garmin Connect.'
    }

    Write-Log -Message "    >> Last activity: $($activity.activityId)"

    if ($Raw) {
        $result = $activity
    }
    else {
        $distanceKm = $null
        if ($null -ne $activity.distance) {
            $distanceKm = [math]::Round(([double]$activity.distance / 1000.0), 2)
        }

        $result = [pscustomobject]@{
            Connected           = $true
            ActivityId          = $activity.activityId
            ActivityName        = $activity.activityName
            ActivityType        = $activity.activityType.typeKey
            StartTimeLocal      = $activity.startTimeLocal
            DurationSeconds     = if ($null -ne $activity.duration) { $activity.duration } else { $activity.elapsedDuration }
            DistanceKm          = $distanceKm
            ElevationGainMeters = $activity.elevationGain
        }
    }

    Invoke-Output -Type Success -Message "Last Garmin Connect activity fetched successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
