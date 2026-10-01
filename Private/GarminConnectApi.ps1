################################################################################
#####                                                                      #####
#####    Native Garmin Connect API access (pure PowerShell)                #####
#####    Uses the DI OAuth2 token store written by Get-GarminToken         #####
#####                                                                      #####
################################################################################

$Script:GarminConnectApiBase = 'https://connectapi.garmin.com'
$Script:GarminDiTokenUrl = 'https://diauth.garmin.com/di-oauth2-service/oauth/token'

function Get-GarminNativeHeaders {
    # Headers of the Garmin Connect Android app
    param(
        [hashtable]$Extra = @{}
    )

    $headers = @{
        'User-Agent'                  = 'GCM-Android-5.23'
        'X-Garmin-User-Agent'         = 'com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0'
        'X-Garmin-Paired-App-Version' = '10861'
        'X-Garmin-Client-Platform'    = 'Android'
        'X-App-Ver'                   = '10861'
        'X-Lang'                      = 'en'
        'X-GCExperience'              = 'GC5'
        'Accept-Language'             = 'en-US,en;q=0.9'
    }
    foreach ($key in $Extra.Keys) {
        $headers[$key] = $Extra[$key]
    }
    return $headers
}

function ConvertFrom-GarminJwtPayload {
    # Decodes the JWT payload without verifying the signature (only Garmin has the key)
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $parts = $Token.Split('.')
    if ($parts.Count -lt 2) {
        return $null
    }

    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    $payload += '=' * ((4 - $payload.Length % 4) % 4)
    try {
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Resolve-GarminTokenFile {
    # A directory (default ~/.garminconnect) means <dir>\garmin_tokens.json
    param(
        [string]$TokenStore
    )

    if ([string]::IsNullOrWhiteSpace($TokenStore)) {
        $TokenStore = [Environment]::GetEnvironmentVariable('GARMINTOKENS', 'Process')
    }
    if ([string]::IsNullOrWhiteSpace($TokenStore)) {
        $TokenStore = Join-Path -Path $HOME -ChildPath '.garminconnect'
    }

    $path = [System.IO.Path]::GetFullPath($TokenStore.Replace('~', $HOME))
    if ((Test-Path -LiteralPath $path -PathType Container) -or [System.IO.Path]::GetExtension($path) -ne '.json') {
        return Join-Path -Path $path -ChildPath 'garmin_tokens.json'
    }
    return $path
}

function Get-GarminAccessToken {
    # Returns a valid DI access token; refreshes it (and updates the token file) when it expires within 15 minutes
    param(
        [string]$TokenStore
    )

    $tokenFile = Resolve-GarminTokenFile -TokenStore $TokenStore
    if (-not (Test-Path -LiteralPath $tokenFile -PathType Leaf)) {
        throw "No Garmin token file found at '$tokenFile'. Sign in first with Get-GarminToken."
    }

    $store = Get-Content -LiteralPath $tokenFile -Raw | ConvertFrom-Json
    if (-not $store.di_token) {
        throw "The token file '$tokenFile' contains no DI token. Sign in again with Get-GarminToken."
    }

    $payload = ConvertFrom-GarminJwtPayload -Token $store.di_token
    $expiresSoon = $payload -and $payload.exp -and ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -gt ([long]$payload.exp - 900))
    if (-not $expiresSoon) {
        return $store.di_token
    }

    Write-Log -Message "    >> DI token expires soon, refreshing ($tokenFile)"
    if (-not $store.di_refresh_token -or -not $store.di_client_id) {
        throw 'The Garmin access token has expired and no refresh token is available. Sign in again with Get-GarminToken.'
    }

    $basicAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($store.di_client_id):"))
    $response = Invoke-WebRequest -Method Post -Uri $Script:GarminDiTokenUrl -SkipHttpErrorCheck `
        -Headers (Get-GarminNativeHeaders -Extra @{ Authorization = $basicAuth; Accept = 'application/json'; 'Cache-Control' = 'no-cache' }) `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{ grant_type = 'refresh_token'; client_id = $store.di_client_id; refresh_token = $store.di_refresh_token }

    if ([int]$response.StatusCode -ne 200) {
        throw "Garmin token refresh failed (HTTP $([int]$response.StatusCode)). Sign in again with Get-GarminToken."
    }

    $data = $response.Content | ConvertFrom-Json
    $newPayload = ConvertFrom-GarminJwtPayload -Token $data.access_token
    $updatedStore = [pscustomobject][ordered]@{
        di_token         = $data.access_token
        di_refresh_token = if ($data.PSObject.Properties['refresh_token'] -and $data.refresh_token) { $data.refresh_token } else { $store.di_refresh_token }
        di_client_id     = if ($newPayload -and $newPayload.client_id) { [string]$newPayload.client_id } else { $store.di_client_id }
    }
    $updatedStore | ConvertTo-Json -Compress | Set-Content -LiteralPath $tokenFile -Encoding utf8NoBOM

    return $updatedStore.di_token
}

function Invoke-GarminConnectApi {
    # Calls connectapi.garmin.com with the stored DI bearer token.
    # -Query:   array values are sent as repeated parameters (metricId=22&metricId=23), booleans as true/false
    # -Body:    object sent as JSON (POST/PUT)
    # -Form:    multipart/form-data upload, e.g. @{ file = Get-Item .\activity.fit }
    # -OutFile: saves the raw response (FIT/TCX/GPX/ZIP downloads) instead of parsing JSON
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [System.Collections.IDictionary]$Query = @{},

        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string]$Method = 'Get',

        [object]$Body,

        [hashtable]$Form,

        [string]$OutFile,

        [string]$TokenStore
    )

    $accessToken = Get-GarminAccessToken -TokenStore $TokenStore
    $uri = $Script:GarminConnectApiBase + '/' + $Path.TrimStart('/')
    if ($Query.Count -gt 0) {
        $pairs = foreach ($entry in $Query.GetEnumerator()) {
            foreach ($value in @($entry.Value)) {
                $text = if ($value -is [bool]) { $value.ToString().ToLower() } else { [string]$value }
                '{0}={1}' -f [Uri]::EscapeDataString([string]$entry.Key), [Uri]::EscapeDataString($text)
            }
        }
        $uri += '?' + ($pairs -join '&')
    }

    $request = @{
        Method             = $Method
        Uri                = $uri
        SkipHttpErrorCheck = $true
        Headers            = Get-GarminNativeHeaders -Extra @{ Authorization = "Bearer $accessToken"; Accept = $(if ($OutFile) { '*/*' } else { 'application/json' }) }
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 100 -Compress }
        $request.ContentType = 'application/json'
    }
    if ($PSBoundParameters.ContainsKey('Form')) {
        $request.Form = $Form
    }

    $response = Invoke-WebRequest @request

    $status = [int]$response.StatusCode
    switch ($status) {
        { $_ -in 200, 201, 202 } {
            if ($OutFile) {
                [System.IO.File]::WriteAllBytes([System.IO.Path]::GetFullPath($OutFile), $response.RawContentStream.ToArray())
                return Get-Item -LiteralPath $OutFile
            }
            $content = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
            if ([string]::IsNullOrWhiteSpace($content)) { return $null }
            return $content | ConvertFrom-Json -Depth 100
        }
        204 { return $null }
        409 { throw "Garmin API $Path : conflict (409), e.g. the activity already exists." }
        401 { throw "Garmin API $Path : authentication required (401). Sign in again with Get-GarminToken." }
        403 { throw "Garmin API $Path : access denied (403)." }
        404 { throw "Garmin API $Path : not found (404), the endpoint may have moved." }
        429 { throw "Garmin API $Path : rate limited (429), please wait before retrying." }
        default { throw "Garmin API $Path : HTTP $status." }
    }
}
