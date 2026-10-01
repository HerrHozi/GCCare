<#
.SYNOPSIS
Fetches the earned Garmin Connect badges and summarizes them by year or month.

.DESCRIPTION
`Get-GarminBadges` executes `Corefunctions\connectToGarmin.py`, which logs in to
Garmin Connect and returns the earned badges as PowerShell objects.

The function automatically detects a Python executable (`py` or `python`) from PATH.
If a token store path is provided, it is passed to the Python script through
the `GARMINTOKENS` environment variable (restored afterwards).

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
Optional path to the Garmin Connect token store directory. Passed to the Python
script via the `GARMINTOKENS` environment variable for the duration of the call.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.PARAMETER GroupBy
Optional summary interval. Valid values: `Year`, `Month`, `Name`.
- `Year`:  One row per year plus a 'Total' row, with badge count, points, and cumulative points.
- `Month`: One row per year and month plus a 'Total' row, with badge count, points, and cumulative points.
- `Name`:  Accepted by parameter validation, but currently has no effect; the raw badges are returned.

If omitted, the individual badges are returned.

.OUTPUTS
System.Object[]
Returns the earned badges, or summary objects (`Year`, `Month`, `BadgeCount`, `Points`,
`TotalPoints`) when `-GroupBy Year` or `-GroupBy Month` is specified.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`.
- Requires Python (`py.exe` or `python.exe`) available in PATH.
- Requires the bundled script:
    `<ModuleRoot>\Corefunctions\connectToGarmin.py`.
- Badge retrieval is delegated to the Python script; non-zero exit codes are treated as errors.
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
Get-GarminBadges -GroupBy Month | Where-Object { $_.Year -eq 2025 } | Sort-Object Points -Descending | Select-Object -First 3

Returns the three months of 2025 in which the most badge points were earned.
#>
Function Get-GarminBadgesPy {

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

    $Levels = [ordered]@{
        1  = 0
        2  = 20
        3  = 60
        4  = 140
        5  = 300
        6  = 620
        7  = 1260
        8  = 2540
        9  = 5100
        10 = 10220
    }

    Invoke-Output -Type Header -Message "Fetching earned Garmin Connect badges..."
    
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $pythonScriptPath = Join-Path -Path $moduleRoot -ChildPath 'Corefunctions\connectToGarmin.py'

    if (-not (Test-Path -LiteralPath $pythonScriptPath -PathType Leaf)) {
        throw "Python script not found: $pythonScriptPath"
    }

    $pythonCommand = $null
    foreach ($candidate in @('py', 'python')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            $pythonCommand = $command.Source
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($pythonCommand)) {
        throw 'Python executable not found. Install Python and ensure py.exe or python.exe is in PATH.'
    }

    $previousTokenStore = [Environment]::GetEnvironmentVariable('GARMINTOKENS', 'Process')

    try {
        if ($PSBoundParameters.ContainsKey('TokenStore') -and -not [string]::IsNullOrWhiteSpace($TokenStore)) {
            $resolvedTokenStore = [System.IO.Path]::GetFullPath($TokenStore)
            [Environment]::SetEnvironmentVariable('GARMINTOKENS', $resolvedTokenStore, 'Process')
            #Invoke-Output -Type Info -Message "Token store: $resolvedTokenStore"
        }

        $pythonOutput = & $pythonCommand $pythonScriptPath '--badges-json'

        if ($LASTEXITCODE -ne 0) {
            throw "Python script failed with exit code $LASTEXITCODE."
        }

        $badgesJson = $pythonOutput -join [Environment]::NewLine
        $badges = ConvertFrom-Json -InputObject $badgesJson
        
        write-host ""
        Invoke-Output -Type Bullet  -Message "Total Badges:  " -TextMaker $($badges.Count) -NoExtraLines
  
        $allBadges = @($badges)
        $totalPoints = ($allBadges | ForEach-Object {
                [double]$_.badgePoints * [double]$_.badgeEarnedNumber
            } | Measure-Object -Sum).Sum

        if ($null -eq $totalPoints) {
            $totalPoints = 0
        }

        $CurrentLevel = ($Levels.GetEnumerator() |
            Where-Object { $totalPoints -ge $_.Value } |
            Select-Object -Last 1).Key

        if ($CurrentLevel -lt 10) {
            $NextLevel = $CurrentLevel + 1
            $NextPoints = $Levels[$NextLevel - 1]
            $Missing = $NextPoints - $totalPoints

            Invoke-Output -Type Bullet  -Message "Total Points:  " -TextMaker $totalPoints -NoExtraLines
            Invoke-Output -Type Bullet  -Message "Current Level: " -TextMaker $CurrentLevel -NoExtraLines
            Invoke-Output -Type Bullet  -Message "Next Level:    " -TextMaker "$NextLevel ($NextPoints Points)"
            Invoke-Output -Type Bullet  -Message "Points Missing:" -TextMaker $Missing
        }
        else {
            Invoke-Output -Type Textmaker  -Message "Level 10 reached." -TextMaker "(highest)"
        }



    }
    finally {
        [Environment]::SetEnvironmentVariable('GARMINTOKENS', $previousTokenStore, 'Process')
    }


    if ($GroupBy -eq 'Year') {
        $badgeSummary = @()
        $allBadges = @($badges)
        $totalPoints = ($allBadges | ForEach-Object {
                [double]$_.badgePoints * [double]$_.badgeEarnedNumber
            } | Measure-Object -Sum).Sum

        if ($null -eq $totalPoints) {
            $totalPoints = 0
        }

        $badgeSummary += [pscustomobject]@{
            Year        = 'Total'
            BadgeCount  = $allBadges.Count
            Points      = $totalPoints
            TotalPoints = $totalPoints
        }

        $badgesByYear = $allBadges |
        Where-Object { $_.badgeEarnedDate } |
        Group-Object -Property {
            [datetime]::Parse(
                [string]$_.badgeEarnedDate,
                [Globalization.CultureInfo]::InvariantCulture
            ).Year
        } |
        Sort-Object { [int]$_.Name }

        $runningTotalPoints = 0
        foreach ($yearGroup in $badgesByYear) {
            $yearPoints = ($yearGroup.Group | ForEach-Object {
                    [double]$_.badgePoints * [double]$_.badgeEarnedNumber
                } | Measure-Object -Sum).Sum

            if ($null -eq $yearPoints) {
                $yearPoints = 0
            }

            $runningTotalPoints += $yearPoints
            $badgeSummary += [pscustomobject]@{
                Year        = [string]$yearGroup.Name
                BadgeCount  = $yearGroup.Count
                Points      = $yearPoints
                TotalPoints = $runningTotalPoints
            }
        }
        <#

        foreach ($summaryRow in $badgeSummary) {
            if ($summaryRow.Year -eq 'Total') {
                Invoke-Output -Type Bullet -Message 'Total:' -TextMaker "Badges: $($summaryRow.BadgeCount), points: $($summaryRow.Points)"
            }
            else {
                Invoke-Output -Type Bullet -Message "Year $($summaryRow.Year):" -TextMaker "Badges: $($summaryRow.BadgeCount), points: $($summaryRow.Points)"
            }
        }
        #>

        $badges = $badgeSummary
    }

    if ($GroupBy -eq 'Month') {
        $badgeSummary = @()
        $allBadges = @($badges)
        $totalPoints = ($allBadges | ForEach-Object {
                [double]$_.badgePoints * [double]$_.badgeEarnedNumber
            } | Measure-Object -Sum).Sum

        if ($null -eq $totalPoints) {
            $totalPoints = 0
        }

        $badgeSummary += [pscustomobject]@{
            Year        = 'Total'
            Month       = ''
            BadgeCount  = $allBadges.Count
            Points      = $totalPoints
            TotalPoints = $totalPoints
        }

        $badgesByMonth = $allBadges |
        Where-Object { $_.badgeEarnedDate } |
        Group-Object -Property {
            $earnedDate = [datetime]::Parse(
                [string]$_.badgeEarnedDate,
                [Globalization.CultureInfo]::InvariantCulture
            )
            '{0:D4}-{1:D2}' -f $earnedDate.Year, $earnedDate.Month
        } |
        Sort-Object { [int]($_.Name -split '-')[0] }, { [int]($_.Name -split '-')[1] }

        $runningTotalPoints = 0
        foreach ($monthGroup in $badgesByMonth) {
            $monthPoints = ($monthGroup.Group | ForEach-Object {
                    [double]$_.badgePoints * [double]$_.badgeEarnedNumber
                } | Measure-Object -Sum).Sum

            if ($null -eq $monthPoints) {
                $monthPoints = 0
            }

            $runningTotalPoints += $monthPoints
            $yearMonth = $monthGroup.Name -split '-'
            $badgeSummary += [pscustomobject]@{
                Year        = $yearMonth[0]
                Month       = $yearMonth[1]
                BadgeCount  = $monthGroup.Count
                Points      = $monthPoints
                TotalPoints = $runningTotalPoints
            }
        }

        $badges = $badgeSummary
    }


    

    Invoke-Output -Type Success -Message "Garmin Connect badges fetched successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $badges

}