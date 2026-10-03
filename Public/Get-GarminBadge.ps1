<#
.SYNOPSIS
Fetches earned, available or non-completed Garmin Connect badges and summarizes them by year, month or name.

.DESCRIPTION
`Get-GarminBadge` calls the Garmin Connect API directly from PowerShell. Authentication
uses the DI OAuth2 token store written by `Get-GarminToken` (`gctoken.json`). An access
token that expires within 15 minutes is refreshed automatically and saved back.

`-Type` selects the badges:
- `Earned` (default):  Badges earned by the user (`/badge-service/badge/earned`).
- `Available`:         Badges not earned yet (`/badge-service/badge/available`, `earnedByMe = false`).
- `NonCompleted`:      Joined badge challenges that are not completed yet
                       (`/badgechallenge-service/badgeChallenge/non-completed`, `badgeEarnedDate` empty).
                       All pages of the endpoint are fetched.

Before returning, the function writes a console summary. For `Earned`: total number of
badges, total points (badge points multiplied by the number of times each badge was
earned), the current Garmin level (1-10), the next level threshold, and the points still
missing. For `Available` and `NonCompleted`: number of badges and the points that can
still be earned.

Without `-GroupBy`, the badge objects are returned. With `-GroupBy Year` or
`-GroupBy Month`, the badges are aggregated by date and summary objects are returned
instead. The date is the earned date (`Earned`), the badge end date (`Available`) or the
challenge end date (`NonCompleted`). The first summary row always has `Year = 'Total'`;
the following rows are sorted chronologically and contain a running `TotalPoints` value.
Badges without a date are summarized in a last row with `Year = 'None'`.

Summary object properties:
- Year:        'Total', the four-digit year, or 'None'.
- Month:       Two-digit month (only with `-GroupBy Month`; empty for the 'Total' and 'None' rows).
- BadgeCount:  Number of badges in the period.
- Points:      Points in the period.
- TotalPoints: Cumulative points up to and including the period.

With `-CustomSelection`, the Where-Object filter and the Select-Object properties for the
selected type are read from `$env:USERPROFILE\GCCare\Config\GCCare.json`
(section `GarminConnectApi > CustomSelection > Badge > <Type>`; the file is copied
from the module on import if it does not exist yet). `-Filter` and `-Property` override
these values for one call, `-SaveCustomSelection` stores them in `GCCare.json`.
Together with `-GroupBy`, only the filter is applied before grouping; the properties are
ignored.

Because the result consists of objects, it can be filtered and formatted with
standard cmdlets such as `Where-Object`, `Sort-Object`, and `Format-Table`.
Note that `Year` and `Month` are strings.

.PARAMETER Type
Badges to fetch. Valid values: `Earned` (default), `Available`, `NonCompleted`.

.PARAMETER GroupBy
Optional summary interval. Valid values: `Year`, `Month`, `Name`.
- `Year`:  One row per year plus a 'Total' row, with badge count, points, and cumulative points.
- `Month`: One row per year and month plus a 'Total' row, with badge count, points, and cumulative points.
- `Name`:  One row per badge (Name, EarnedCount, BadgePoints, Points, LastEarned), sorted by points.
           Only with `-Type Earned`.

If omitted, the individual badges are returned.

.PARAMETER CustomSelection
Applies the Where-Object filter and the Select-Object properties stored in `GCCare.json`
for the selected type.

.PARAMETER Filter
Where-Object filter for this call, e.g. `{ $_.badgePoints -ge 2 }`. Overrides the value
from `GCCare.json` and implies `-CustomSelection`.

.PARAMETER Property
Select-Object properties for this call, e.g. `badgeName, badgePoints`. Overrides the
value from `GCCare.json` and implies `-CustomSelection`.

.PARAMETER SaveCustomSelection
Saves `-Filter` and/or `-Property` for the selected type in
`$env:USERPROFILE\GCCare\Config\GCCare.json`. Requires `-Filter` or `-Property`.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `gctoken.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Object[]
Returns the badges, or summary objects when `-GroupBy` is specified.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`,
  `Get-GarminEarnedBadgeList`, `Get-GarminAvailableBadgeList`, `Get-GarminNonCompletedBadgeList`,
  `Get-GCCareCustomSelection`, `Save-GCCareCustomSelection`.
- Requires a token file created by `Get-GarminToken`.
- The Where-Object value in `GCCare.json` is executed as PowerShell code. Only store
  filters you trust.
- Alias: `Get-GarminBadges`.

.EXAMPLE
Get-GarminBadge

Returns the earned Garmin Connect badges and shows the level summary in the console.

.EXAMPLE
Get-GarminBadge -TokenStore "C:\Temp\.garminconnect"

Fetches earned badges using a custom token store.

.EXAMPLE
Get-GarminBadge -GroupBy Year | Format-Table

Shows badge count, points, and cumulative points per year, including a 'Total' row.

.EXAMPLE
Get-GarminBadge -GroupBy Month | Where-Object { $_.Year -eq 2025 } | Format-Table

Shows the monthly badge count, points, and cumulative points for 2025 only.

.EXAMPLE
Get-GarminBadge -GroupBy Name | Select-Object -First 10 | Format-Table

Shows the ten badges that earned the most points.

.EXAMPLE
Get-GarminBadge -Type Available -CustomSelection | Format-Table

Returns the badges not earned yet with the filter and properties from `GCCare.json`.

.EXAMPLE
Get-GarminBadge -Type Available -GroupBy Month | Format-Table

Shows per month how many available badges end and how many points they are worth.

.EXAMPLE
Get-GarminBadge -Type NonCompleted -CustomSelection | Format-Table

Returns the joined, not completed challenges with name, end date, target and progress.

.EXAMPLE
Get-GarminBadge -Type NonCompleted -Property badgeChallengeName, endDate, badgeProgressValue, badgeTargetValue -SaveCustomSelection

Saves the properties for `NonCompleted` in `GCCare.json` and returns the challenges with them.
#>
Function Get-GarminBadge {

    [CmdletBinding()]
    [Alias('Get-GarminBadges')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Earned', 'Available', 'NonCompleted')]
        [string]$Type = 'Earned',
        [ValidateSet('Year', 'Month', 'Name')]
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

    if ($GroupBy -eq 'Name' -and $Type -ne 'Earned') {
        throw "-GroupBy Name is only supported for -Type Earned."
    }
    if ($SaveCustomSelection -and -not ($PSBoundParameters.ContainsKey('Filter') -or $PSBoundParameters.ContainsKey('Property'))) {
        throw "-SaveCustomSelection requires -Filter and/or -Property."
    }
    $useCustomSelection = $CustomSelection -or $PSBoundParameters.ContainsKey('Filter') -or $PSBoundParameters.ContainsKey('Property')

    # Minimum points required for Garmin levels 1-10 (index 0 = level 1)
    $LevelThresholds = @(0, 20, 60, 140, 300, 620, 1260, 2540, 5100, 10220)

    # Earned: points x times earned; Available/NonCompleted: points that can be earned
    function Get-BadgePoints($BadgeList) {
        $sum = (@($BadgeList) | ForEach-Object {
                if ($Type -eq 'Earned') { [double]$_.badgePoints * [double]$_.badgeEarnedNumber } else { [double]$_.badgePoints }
            } | Measure-Object -Sum).Sum
        if ($null -eq $sum) { 0 } else { $sum }
    }

    function ConvertTo-BadgeDate($Value) {
        if ($Value -is [datetime]) { $Value } else { [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture) }
    }

    $typeText = @{ Earned = 'earned'; Available = 'available'; NonCompleted = 'non-completed' }[$Type]
    $dateProperty = @{ Earned = 'badgeEarnedDate'; Available = 'badgeEndDate'; NonCompleted = 'endDate' }[$Type]

    Invoke-Output -Type Header -Message "Fetching $typeText Garmin Connect badges..."

    $allBadges = switch ($Type) {
        'Earned' { Get-GarminEarnedBadgeList -TokenStore $TokenStore }
        'Available' { Get-GarminAvailableBadgeList -TokenStore $TokenStore }
        'NonCompleted' { Get-GarminNonCompletedBadgeList -TokenStore $TokenStore }
    }
    $allBadges = @($allBadges)

    # Console summary
    $totalPoints = Get-BadgePoints $allBadges
    Write-Host ""
    Invoke-Output -Type Bullet -Message "Total Badges:  " -TextMaker $allBadges.Count -NoExtraLines

    if ($Type -eq 'Earned') {
        $CurrentLevel = @($LevelThresholds | Where-Object { $totalPoints -ge $_ }).Count
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
    }
    else {
        Invoke-Output -Type Bullet -Message "Possible Points:" -TextMaker $totalPoints
    }

    # Custom selection: GCCare.json < -Filter / -Property
    $selectProperties = @()
    if ($useCustomSelection) {
        if ($SaveCustomSelection) {
            $saveParams = @{ Section = 'Badge'; Name = $Type }
            if ($PSBoundParameters.ContainsKey('Filter')) { $saveParams.Filter = $Filter }
            if ($PSBoundParameters.ContainsKey('Property')) { $saveParams.Property = $Property }
            Save-GCCareCustomSelection @saveParams
        }

        $selection = Get-GCCareCustomSelection -Section 'Badge' -Name $Type
        $whereFilter = if ($PSBoundParameters.ContainsKey('Filter')) { $Filter } else { $selection.Filter }
        $selectProperties = if ($PSBoundParameters.ContainsKey('Property')) { @($Property) } else { @($selection.Property) }

        if ($whereFilter) {
            $allBadges = @($allBadges | Where-Object -FilterScript $whereFilter)
            Write-Log -Message "    >> Filter {$whereFilter}: $($allBadges.Count) badges left"
        }
    }

    $result = $allBadges

    if ($GroupBy -in 'Year', 'Month') {
        $byMonth = $GroupBy -eq 'Month'
        $groupPoints = Get-BadgePoints $allBadges

        $totalRow = [ordered]@{ Year = 'Total' }
        if ($byMonth) { $totalRow.Month = '' }
        $totalRow.BadgeCount = $allBadges.Count
        $totalRow.Points = $groupPoints
        $totalRow.TotalPoints = $groupPoints
        $badgeSummary = @([pscustomobject]$totalRow)

        # Group keys 'yyyy' or 'yyyy-MM' sort chronologically as plain strings
        $groups = $allBadges |
            Where-Object { $_.$dateProperty } |
            Group-Object -Property { (ConvertTo-BadgeDate $_.$dateProperty).ToString($(if ($byMonth) { 'yyyy-MM' } else { 'yyyy' })) } |
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

        # Badges without a date (e.g. available badges without end date)
        $undated = @($allBadges | Where-Object { -not $_.$dateProperty })
        if ($undated.Count -gt 0) {
            $points = Get-BadgePoints $undated
            $runningTotalPoints += $points

            $row = [ordered]@{ Year = 'None' }
            if ($byMonth) { $row.Month = '' }
            $row.BadgeCount = $undated.Count
            $row.Points = $points
            $row.TotalPoints = $runningTotalPoints
            $badgeSummary += [pscustomobject]$row
        }

        $result = $badgeSummary
    }
    elseif ($GroupBy -eq 'Name') {
        $result = $allBadges | ForEach-Object {
            [pscustomobject]@{
                Name        = $_.badgeName
                EarnedCount = [int]$_.badgeEarnedNumber
                BadgePoints = [double]$_.badgePoints
                Points      = [double]$_.badgePoints * [double]$_.badgeEarnedNumber
                LastEarned  = if ($_.badgeEarnedDate) { ConvertTo-BadgeDate $_.badgeEarnedDate } else { $null }
            }
        } | Sort-Object -Property @{ Expression = 'Points'; Descending = $true }, Name
    }
    elseif ($selectProperties.Count -gt 0) {
        $result = $allBadges | Select-Object -Property $selectProperties
    }

    Invoke-Output -Type Success -Message "Garmin Connect badges fetched successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
