<#
.SYNOPSIS
Fetches the Garmin Connect user profile and personal settings.

.DESCRIPTION
`Get-GarminUser` calls the Garmin Connect API endpoints
`/userprofile-service/socialProfile` and `/userprofile-service/userprofile/user-settings`
directly from PowerShell. Authentication uses the DI OAuth2 token store
written by `Get-GarminToken` (`gctoken.json`). An access token that
expires within 15 minutes is refreshed automatically and saved back.

Returns a summary object with these properties:
- Connected:                 Always `$true` when the call succeeded.
- DisplayName:               Garmin display name (used in many API paths).
- FullName:                  Full name of the user.
- UserName:                  Garmin user name (usually the e-mail address).
- ProfileId:                 Numeric user profile ID (`userProfilePk`, e.g. for gear queries).
- Location:                  Location from the social profile.
- Level:                     Garmin Connect level.
- Points:                    Garmin Connect points.
- Gender:                    Gender from the user settings.
- BirthDate:                 Birth date (`yyyy-MM-dd`).
- Age:                       Age in years, calculated from the birth date.
- HeightCm:                  Height in centimeters.
- WeightKg:                  Weight in kilograms (Garmin stores grams).
- MeasurementSystem:         Unit system, e.g. `metric`.
- VO2MaxRunning:             VO2 max for running.
- VO2MaxCycling:             VO2 max for cycling.
- LactateThresholdHeartRate: Lactate threshold heart rate.

Properties that Garmin does not return for an account are `$null`.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `gctoken.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER Raw
Optional switch to return the unmodified API objects (`SocialProfile`, `UserSettings`)
instead of the summary.

.PARAMETER Quiet
Optional switch to suppress the console output (header, summary and success message).
Only the result object is returned.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns the user summary, or the raw API objects with `-Raw`.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`.
- Requires a token file created by `Get-GarminToken`.

.EXAMPLE
Get-GarminUser

Returns a summary of the Garmin Connect user.

.EXAMPLE
(Get-GarminUser).DisplayName

Returns the display name, e.g. for API paths like `/usersummary-service/usersummary/daily/{displayName}`.

.EXAMPLE
$user = Get-GarminUser -Quiet

Fetches the user profile without console output, e.g. for use in other functions.

.EXAMPLE
Get-GarminUser -Raw | Select-Object -ExpandProperty UserSettings

Returns the complete user settings as delivered by the API.
#>
function Get-GarminUser {

    [CmdletBinding()]
    param(
        [string]$TokenStore,
        [switch]$Raw,
        [switch]$EnableLogging,
        [switch]$Quiet
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################
    If (-not $Quiet) {
        Invoke-Output -Type Header -Message "Fetching Garmin Connect user profile..."
    }
 

    $socialProfile = Invoke-GarminConnectApi -Path '/userprofile-service/socialProfile' -TokenStore $TokenStore
    if ($null -eq $socialProfile) {
        throw 'Connected, but no user profile was returned by Garmin Connect.'
    }

    $userSettings = Invoke-GarminConnectApi -Path '/userprofile-service/userprofile/user-settings' -TokenStore $TokenStore
    Write-Log -Message "    >> User profile: $($socialProfile.profileId)"

    if ($Raw) {
        $result = [pscustomobject]@{
            SocialProfile = $socialProfile
            UserSettings  = $userSettings
        }
    }
    else {
        $userData = if ($null -ne $userSettings) { $userSettings.userData } else { $null }

        $birthDate = $null
        $age = $null
        if ($userData -and $userData.birthDate) {
            $birthDate = [datetime]::Parse([string]$userData.birthDate, [Globalization.CultureInfo]::InvariantCulture)
            $today = (Get-Date).Date
            $age = $today.Year - $birthDate.Year
            if ($birthDate.Date -gt $today.AddYears(-$age)) {
                $age--
            }
        }

        $weightKg = $null
        if ($userData -and $null -ne $userData.weight) {
            $weightKg = [math]::Round(([double]$userData.weight / 1000.0), 1)
        }

        $result = [pscustomobject]@{
            DisplayName               = $socialProfile.displayName
            Level                     = $socialProfile.userLevel
            Points                    = $socialProfile.userPoint
            FullName                  = $socialProfile.fullName
            Gender                    = $userData.gender
            BirthDate                 = if ($birthDate) { $birthDate.ToString('yyyy-MM-dd') } else { $null }
            HeightCm                  = $userData.height
            WeightKg                  = $weightKg
            Location                  = $socialProfile.location
            MeasurementSystem         = $userData.measurementSystem
            Connected                 = $true
            UserName                  = $socialProfile.userName
            ProfileId                 = $socialProfile.profileId
            Age                       = $age
            VO2MaxRunning             = $userData.vo2MaxRunning
            VO2MaxCycling             = $userData.vo2MaxCycling
            LactateThresholdHeartRate = $userData.lactateThresholdHeartRate
        }

        If (-not $Quiet) {
            Invoke-Output -Type Bullet -Message "Display Name: " -TextMaker $result.DisplayName -NoExtraLines
            Invoke-Output -Type Bullet -Message "Full Name:    " -TextMaker $result.FullName -NoExtraLines
            Invoke-Output -Type Bullet -Message "Profile ID:   " -TextMaker $result.ProfileId
        }
    }
    If (-not $Quiet) {
        Invoke-Output -Type Success -Message "Garmin Connect user profile fetched successfully."
    }
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
