function Get-GarminLastActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session = $Global:GarminLoginSession,

        [switch]$Raw
    )

    if ($null -eq $Session) {
        throw 'No Garmin session found. Run New-GarminLoginSession first.'
    }

    $headers = @{
        'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
        'accept'          = 'application/json, text/plain, */*'
        'accept-language' = 'en-US,en;q=0.9,de;q=0.8'
        'origin'          = 'https://connect.garmin.com'
        'referer'         = 'https://connect.garmin.com/modern/activities'
    }

    $candidateUris = @(
        'https://connect.garmin.com/modern/proxy/activitylist-service/activities/search/activities?start=0&limit=1',
        'https://connect.garmin.com/modern/proxy/activitylist-service/activities/search/activities?start=0&limit=1&sortColumn=startTimeLocal&sortOrder=desc'
    )

    $lastError = $null
    $response = $null

    foreach ($uri in $candidateUris) {
        try {
            $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -WebSession $Session -ErrorAction Stop
            if ($null -ne $response) {
                break
            }
        }
        catch {
            $lastError = $_
        }
    }

    if ($null -eq $response) {
        if ($null -ne $lastError) {
            throw $lastError
        }

        throw 'No response received from Garmin activity endpoints.'
    }

    $responseAsString = [string]$response
    $isSignInHtmlResponse = (
        -not [string]::IsNullOrWhiteSpace($responseAsString) -and
        $responseAsString -match '(?is)<title>\s*Garmin Connect\s*\|\s*Sign In\s*</title>|signin\.astro|please enable JavaScript in your web browser'
    )

    if ($isSignInHtmlResponse) {
        throw 'Garmin session is not authenticated for Connect APIs. The endpoint returned the Sign-In page. Please run New-GarminLoginSession again in the same terminal session.'
    }

    $getFirstActivity = {
        param(
            [Parameter(Mandatory = $true)]
            [object]$InputObject
        )

        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [array]) {
            foreach ($item in $InputObject) {
                $found = & $getFirstActivity -InputObject $item
                if ($null -ne $found) {
                    return $found
                }
            }

            return $null
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            foreach ($item in $InputObject) {
                $found = & $getFirstActivity -InputObject $item
                if ($null -ne $found) {
                    return $found
                }
            }

            return $null
        }

        $propertyBag = $InputObject.PSObject.Properties
        if ($null -eq $propertyBag) {
            return $null
        }

        $looksLikeActivity = (
            $propertyBag.Name -contains 'activityId' -or
            $propertyBag.Name -contains 'activityName' -or
            $propertyBag.Name -contains 'startTimeLocal'
        )

        if ($looksLikeActivity) {
            return $InputObject
        }

        $preferredContainers = @('activities', 'activityList', 'results', 'items', 'data', 'content')
        foreach ($containerName in $preferredContainers) {
            $containerProp = $propertyBag | Where-Object { $_.Name -eq $containerName } | Select-Object -First 1
            if ($null -ne $containerProp) {
                $found = & $getFirstActivity -InputObject $containerProp.Value
                if ($null -ne $found) {
                    return $found
                }
            }
        }

        foreach ($prop in $propertyBag) {
            $found = & $getFirstActivity -InputObject $prop.Value
            if ($null -ne $found) {
                return $found
            }
        }

        return $null
    }

    $activity = $null

    $activity = & $getFirstActivity -InputObject $response

    if ($Raw) {
        return [pscustomobject]@{
            ParsedActivity = $activity
            Response       = $response
            IsSignInHtml   = $isSignInHtmlResponse
        }
    }

    if ($null -eq $activity) {
        throw 'Connected, but no activity could be parsed from response.'
    }

    $activityType = $null
    if ($null -ne $activity.activityType) {
        if ($activity.activityType.PSObject.Properties.Name -contains 'typeKey') {
            $activityType = $activity.activityType.typeKey
        }
        elseif ($activity.activityType -is [string]) {
            $activityType = $activity.activityType
        }
    }

    $durationSeconds = $null
    if ($null -ne $activity.duration) {
        $durationSeconds = $activity.duration
    }
    elseif ($null -ne $activity.elapsedDuration) {
        $durationSeconds = $activity.elapsedDuration
    }

    $distanceKm = $null
    if ($null -ne $activity.distance) {
        $distanceKm = [math]::Round(([double]$activity.distance / 1000.0), 2)
    }

    return [pscustomobject]@{
        Connected           = $true
        ActivityId          = $activity.activityId
        ActivityName        = $activity.activityName
        ActivityType        = $activityType
        StartTimeLocal      = $activity.startTimeLocal
        DurationSeconds     = $durationSeconds
        DistanceKm          = $distanceKm
        ElevationGainMeters = $activity.elevationGain
    }
}
