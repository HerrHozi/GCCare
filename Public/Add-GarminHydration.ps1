<#
.SYNOPSIS
Adds a hydration (water intake) entry to Garmin Connect, optionally for the last X days.

.DESCRIPTION
`Add-GarminHydration` calls the Garmin Connect API endpoint
`/usersummary-service/usersummary/hydration/log` directly from PowerShell.
Authentication uses the DI OAuth2 token store written by `Get-GarminToken`
(`gctoken.json`). An access token that expires within 15 minutes is
refreshed automatically and saved back.

The amount is added to the daily hydration of `-Date` (default: today). With `-LastX`,
the same amount is also added to the days before, including `-Date`: `-LastX 7` logs
today and the six days before. The time of day of `-Date` is used for every entry.
A negative amount reduces the daily hydration, e.g. to correct a wrong entry.

Decimal numbers may be entered with '.' or ',' as decimal separator.

Returns one summary object per day with these properties:
- Date:        Calendar date of the entry.
- AddedML:     Amount added in milliliters.
- TotalML:     Daily hydration in milliliters after the entry.
- GoalML:      Daily hydration goal in milliliters.
- GoalPercent: Share of the daily goal in percent (TotalML / GoalML * 100, rounded;
               may exceed 100, empty without a goal).
- Status:      `Added` or `WhatIf`.

.PARAMETER ValueInML
Amount of water in milliliters. Mandatory. Alias: `-ML`.

.PARAMETER Date
Date and time of the (latest) entry. Default: now.

.PARAMETER LastX
Number of days to log, counted back from `-Date` and including it. Default: 1.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `gctoken.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER Quiet
Suppresses the console output.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one summary object per logged day (oldest first).

.NOTES
- Requires helper functions in module scope:
  `Measure-FunctionRuntime`, `Write-Log`, `Invoke-Output`, `Invoke-GarminConnectApi`,
  `Get-GCCareArgumentText`, `ConvertTo-GCCareDecimal`.
- Requires a token file created by `Get-GarminToken`.
- Supports `-WhatIf`: the entries are shown, but not sent.
- Alias: `Add-Hydration`.

.EXAMPLE
Add-GarminHydration -ValueInML 500

Adds 500 ml to today's hydration.

.EXAMPLE
Add-GarminHydration 500 -LastX 7

Adds 500 ml to today and to each of the six days before.

.EXAMPLE
Add-GarminHydration 250 -Date '2026-10-10 18:30'

Adds 250 ml to the hydration of 10 October 2026.

.EXAMPLE
Add-GarminHydration -500

Removes 500 ml from today's hydration (correction of a wrong entry).

.EXAMPLE
Add-GarminHydration 500 -LastX 3 -WhatIf

Shows the three entries without sending them to Garmin Connect.
#>
function Add-GarminHydration {

    [CmdletBinding(SupportsShouldProcess = $true)]
    [Alias('Add-Hydration')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('ML')]
        [object]$ValueInML,
        [datetime]$Date = (Get-Date),
        [ValidateRange(1, 365)]
        [int]$LastX = 1,
        [string]$TokenStore,
        [switch]$Quiet,
        [switch]$EnableLogging
    )

    $info = Measure-FunctionRuntime -Begin

    if (-not $Quiet) {
        Invoke-Output -Type Header -Message "Adding hydration to Garmin Connect..."
    }

    if ($Date -gt (Get-Date).AddMinutes(5)) {
        throw "-Date $($Date.ToString('yyyy-MM-dd HH:mm')) is in the future."
    }

    # '.' or ',' as decimal separator (the typed text is used, see Get-GCCareArgumentText)
    $argumentText = Get-GCCareArgumentText -Invocation $MyInvocation
    $amount = [int][math]::Round((ConvertTo-GCCareDecimal -Value $ValueInML -Name 'ValueInML' -ArgumentText $argumentText['ValueInML']), 0)
    if ($amount -eq 0 -or [math]::Abs($amount) -gt 10000) {
        throw "-ValueInML $amount is out of range (-10000 to 10000 ml, not 0)."
    }

    # Oldest day first: -LastX 7 = -Date and the six days before
    $result = for ($dayOffset = $LastX - 1; $dayOffset -ge 0; $dayOffset--) {
        $entryDate = $Date.AddDays(-$dayOffset)
        $calendarDate = $entryDate.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $status = 'WhatIf'
        $totalML = $null
        $goalML = $null
        $goalPercent = $null

        if ($PSCmdlet.ShouldProcess("Garmin Connect", "Add $amount ml hydration on $calendarDate")) {
            $response = Invoke-GarminConnectApi -Path '/usersummary-service/usersummary/hydration/log' -Method Put -TokenStore $TokenStore -Body @{
                calendarDate   = $calendarDate
                timestampLocal = $entryDate.ToString('yyyy-MM-ddTHH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
                valueInML      = $amount
            }

            # The response contains the daily summary; read it if not
            if ($null -eq $response -or $null -eq $response.valueInML) {
                $response = Invoke-GarminConnectApi -Path "/usersummary-service/usersummary/hydration/daily/$calendarDate" -TokenStore $TokenStore
            }
            $status = 'Added'
            $totalML = if ($null -ne $response.valueInML) { [int]$response.valueInML } else { $null }
            $goalML = if ($null -ne $response.goalInML) { [int]$response.goalInML } else { $null }
            # Share of the daily goal; may exceed 100 %, empty without a goal
            if ($goalML -gt 0) { $goalPercent = [int][math]::Round($totalML / $goalML * 100) }
            Write-Log -Message "    >> $calendarDate : $amount ml added, total $totalML / $goalML ml ($goalPercent %)"
        }

        if (-not $Quiet) {
            $totalText = if ($status -eq 'Added') { " (total $totalML / $goalML ml$(if ($null -ne $goalPercent) { " ($goalPercent %)" }))" }
            Invoke-Output -Type Bullet -Message "$calendarDate :" -TextMaker "$amount ml$totalText" -NoExtraLines
        }

        [pscustomobject][ordered]@{
            Date        = $calendarDate
            AddedML     = $amount
            TotalML     = $totalML
            GoalML      = $goalML
            GoalPercent = $goalPercent
            Status      = $status
        }
    }

    if (-not $Quiet) {
        Write-Host ""
        Invoke-Output -Type Success -Message "Hydration added to Garmin Connect ($LastX $(if ($LastX -eq 1) { 'day' } else { 'days' }))."
    }

    Measure-FunctionRuntime -End -Details $info

    return $result
}
