<#
.SYNOPSIS
Fetches the earned Garmin Connect badges and summarizes them by year, month or name.

.DESCRIPTION
`Get-GarminBadges` calls the Garmin Connect API endpoint `/badge-service/badge/earned`
directly from PowerShell. Authentication uses the DI OAuth2 token
store written by `Get-GarminToken` (`garmin_tokens.json`). An access
token that expires within 15 minutes is refreshed automatically and saved back.

Before returning, the function writes a console summary: total number of badges,
total points (badge points multiplied by the number of times each badge was earned),
the current Garmin level (1-10), the next level threshold, and the points still missing.

Without `-GroupBy`, the raw badge objects are returned. With `-GroupBy Year` or
`-GroupBy Month`, the badges are aggregated by the badge earned date and
summary objects are returned instead. The first summary row always has
`Year = 'Total'`; the following rows are sorted chronologically and contain a
running `TotalPoints` value.

Summary object properties:
- Year:        'Total' or the four-digit year.
- Month:       Two-digit month (only with `-GroupBy Month`; empty for the 'Total' row).
- BadgeCount:  Number of badges earned in the period.
- Points:      Points earned in the period.
- TotalPoints: Cumulative points up to and including the period.

Because the result consists of objects, it can be filtered and formatted with
standard cmdlets such as `Where-Object`, `Sort-Object`, and `Format-Table`.
Note that `Year` and `Month` are strings.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `garmin_tokens.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.PARAMETER GroupBy
Optional summary interval. Valid values: `Year`, `Month`, `Name`.
- `Year`:  One row per year plus a 'Total' row, with badge count, points, and cumulative points.
- `Month`: One row per year and month plus a 'Total' row, with badge count, points, and cumulative points.
- `Name`:  One row per badge (Name, EarnedCount, BadgePoints, Points, LastEarned), sorted by points.

If omitted, the individual badges are returned.

.OUTPUTS
System.Object[]
Returns the earned badges, or summary objects when `-GroupBy` is specified.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`.
- Requires a token file created by `Get-GarminToken`.
- Badges without an earned date are excluded from the yearly and monthly rows,
  but are counted in the 'Total' row.

.EXAMPLE
Get-GarminBadges

Returns the earned Garmin Connect badges and shows the level summary in the console.

.EXAMPLE
Get-GarminBadges -TokenStore "C:\Temp\.garminconnect"

Fetches earned badges using a custom token store.

.EXAMPLE
Get-GarminBadges -GroupBy Year | Format-Table

Shows badge count, points, and cumulative points per year, including a 'Total' row.

.EXAMPLE
Get-GarminBadges -GroupBy Month | Where-Object { $_.Year -eq 2025 } | Format-Table

Shows the monthly badge count, points, and cumulative points for 2025 only.

.EXAMPLE
Get-GarminBadges -GroupBy Name | Select-Object -First 10 | Format-Table

Shows the ten badges that earned the most points.
#>
Function Get-GarminBadges {

    [CmdletBinding()]
    param(
        [string]$TokenStore,
        [switch]$EnableLogging,
        [ValidateSet('Year', 'Month', 'Name')]
        [string]$GroupBy
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    # Minimum points required for Garmin levels 1-10 (index 0 = level 1)
    $LevelThresholds = @(0, 20, 60, 140, 300, 620, 1260, 2540, 5100, 10220)

    function Get-BadgePoints($BadgeList) {
        $sum = (@($BadgeList) | ForEach-Object {
                [double]$_.badgePoints * [double]$_.badgeEarnedNumber
            } | Measure-Object -Sum).Sum
        if ($null -eq $sum) { 0 } else { $sum }
    }

    function Get-BadgeEarnedDate($Badge) {
        [datetime]::Parse([string]$Badge.badgeEarnedDate, [Globalization.CultureInfo]::InvariantCulture)
    }

    Invoke-Output -Type Header -Message "Fetching earned Garmin Connect badges..."

    $allBadges = @(Invoke-GarminConnectApi -Path '/badge-service/badge/earned' -TokenStore $TokenStore)
    Write-Log -Message "    >> $($allBadges.Count) badges received"

    # Console summary: badges, points and level
    $totalPoints = Get-BadgePoints $allBadges
    $CurrentLevel = @($LevelThresholds | Where-Object { $totalPoints -ge $_ }).Count

    Write-Host ""
    Invoke-Output -Type Bullet -Message "Total Badges:  " -TextMaker $allBadges.Count -NoExtraLines
    if ($CurrentLevel -lt 10) {
        $NextLevel = $CurrentLevel + 1
        $NextPoints = $LevelThresholds[$NextLevel - 1]
        $Missing = $NextPoints - $totalPoints

        Invoke-Output -Type Bullet -Message "Total Points:  " -TextMaker $totalPoints -NoExtraLines
        Invoke-Output -Type Bullet -Message "Current Level: " -TextMaker $CurrentLevel -NoExtraLines
        Invoke-Output -Type Bullet -Message "Next Level:    " -TextMaker "$NextLevel ($NextPoints Points)"
        Invoke-Output -Type Bullet -Message "Points Missing:" -TextMaker $Missing
    }
    else {
        Invoke-Output -Type Bullet -Message "Total Points:  " -TextMaker $totalPoints -NoExtraLines
        Invoke-Output -Type TextMaker -Message "Level 10 reached." -TextMaker "(highest)"
    }

    $result = $allBadges

    if ($GroupBy -in 'Year', 'Month') {
        $byMonth = $GroupBy -eq 'Month'

        $totalRow = [ordered]@{ Year = 'Total' }
        if ($byMonth) { $totalRow.Month = '' }
        $totalRow.BadgeCount = $allBadges.Count
        $totalRow.Points = $totalPoints
        $totalRow.TotalPoints = $totalPoints
        $badgeSummary = @([pscustomobject]$totalRow)

        # Group keys 'yyyy' or 'yyyy-MM' sort chronologically as plain strings
        $groups = $allBadges |
            Where-Object { $_.badgeEarnedDate } |
            Group-Object -Property { (Get-BadgeEarnedDate $_).ToString($(if ($byMonth) { 'yyyy-MM' } else { 'yyyy' })) } |
            Sort-Object -Property Name

        $runningTotalPoints = 0
        foreach ($group in $groups) {
            $points = Get-BadgePoints $group.Group
            $runningTotalPoints += $points

            $row = [ordered]@{ Year = $group.Name.Substring(0, 4) }
            if ($byMonth) { $row.Month = $group.Name.Substring(5, 2) }
            $row.BadgeCount = $group.Count
            $row.Points = $points
            $row.TotalPoints = $runningTotalPoints
            $badgeSummary += [pscustomobject]$row
        }

        $result = $badgeSummary
    }

    if ($GroupBy -eq 'Name') {
        $result = $allBadges | ForEach-Object {
            [pscustomobject]@{
                Name        = $_.badgeName
                EarnedCount = [int]$_.badgeEarnedNumber
                BadgePoints = [double]$_.badgePoints
                Points      = [double]$_.badgePoints * [double]$_.badgeEarnedNumber
                LastEarned  = if ($_.badgeEarnedDate) { Get-BadgeEarnedDate $_ } else { $null }
            }
        } | Sort-Object -Property @{ Expression = 'Points'; Descending = $true }, Name
    }

    Invoke-Output -Type Success -Message "Garmin Connect badges fetched successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
