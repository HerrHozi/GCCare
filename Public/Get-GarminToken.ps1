#Requires -Version 7.1
<#
.SYNOPSIS
    Signs in to Garmin Connect and creates a DI OAuth2 bearer token.

.DESCRIPTION
    Pure PowerShell port of the login used by the Python library "garminconnect" (0.3.x,
    strategy "mobile+requests"):
      1. POST e-mail/password to the Garmin SSO mobile API (optional MFA code) -> service ticket
      2. Exchange the service ticket at diauth.garmin.com for a DI access + refresh token
      3. With -Refresh: renew the access token from the stored refresh token (no password)

    The token file uses the same format as garminconnect (garmin_tokens.json), so the
    tokens can be shared with GCCare / Connect-GC.

    Note: This is not an official Garmin API. Garmin may change the flow at any time.

.EXAMPLE
    .\Get-GarminToken.ps1 -Test

.EXAMPLE
    $token = .\Get-GarminToken.ps1 -Refresh
    Invoke-RestMethod 'https://connectapi.garmin.com/userprofile-service/socialProfile' `
        -Headers @{ Authorization = "Bearer $($token.AccessToken)"; 'User-Agent' = 'GCM-Android-5.23' }
#>

Function Get-GarminToken {
    [CmdletBinding()]
    param(
        # Token file (same default location and format as garminconnect)
        [string]$TokenFile = (Join-Path $HOME '.garminconnect\garmin_tokens.json'),

        # Skip sign-in: renew the access token with the stored refresh token
        [switch]$Refresh,

        # Verify the token with an API call
        [switch]$Test
    )

    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    $SsoBase = 'https://sso.garmin.com'
    $IosClientId = 'GCM_IOS_DARK'
    $IosServiceUrl = 'https://mobile.integration.garmin.com/gcm/ios'
    $IosLoginUA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'
    $DiTokenUrl = 'https://diauth.garmin.com/di-oauth2-service/oauth/token'
    $DiGrantType = 'https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket'
    $DiClientIds = @(
        'GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2'
        'GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4'
        'GARMIN_CONNECT_MOBILE_ANDROID_DI'
        'GARMIN_CONNECT_MOBILE_IOS_DI'
    )

    #region Helpers

    function Get-NativeHeaders([hashtable]$Extra = @{}) {
        # Headers of the Garmin Connect Android app, used for diauth and connectapi calls
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
        foreach ($key in $Extra.Keys) { $headers[$key] = $Extra[$key] }
        $headers
    }

    function Get-BasicAuth([string]$ClientId) {
        'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${ClientId}:"))
    }

    function ConvertFrom-JwtPayload([string]$Token) {
        # Decodes the JWT payload without verifying the signature (only Garmin has the key)
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $null }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        $payload += '=' * ((4 - $payload.Length % 4) % 4)
        try {
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        }
        catch {
            $null
        }
    }

    function ConvertFrom-JsonResponse($Response, [string]$Step) {
        $status = [int]$Response.StatusCode
        if ($status -eq 429) {
            throw "$Step was rate limited by Garmin (HTTP 429). Wait at least an hour before trying again."
        }
        if ($status -eq 403) {
            throw "$Step was blocked by Garmin's Cloudflare protection (HTTP 403). Try again later, from another network, or use Connect-GC (Python, TLS impersonation)."
        }
        try {
            $Response.Content | ConvertFrom-Json
        }
        catch {
            throw "$Step failed: HTTP $status, response is not JSON."
        }
    }

    #endregion

    #region Garmin flow

    function Invoke-GarminMobileLogin([pscredential]$Credential) {
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $query = "clientId=$IosClientId&locale=en-US&service=$([Uri]::EscapeDataString($IosServiceUrl))"
        $headers = @{
            'User-Agent' = $IosLoginUA
            'Accept'     = 'application/json, text/plain, */*'
            'Origin'     = $SsoBase
        }
        $request = @{
            Method             = 'Post'
            WebSession         = $session
            Headers            = $headers
            ContentType        = 'application/json'
            SkipHttpErrorCheck = $true
        }

        # 1) Send credentials
        $body = @{
            username     = $Credential.UserName.Trim()
            password     = $Credential.GetNetworkCredential().Password
            rememberMe   = $true
            captchaToken = ''
        } | ConvertTo-Json -Compress
        $resp = Invoke-WebRequest @request -Uri "$SsoBase/mobile/api/login?$query" -Body $body
        $result = ConvertFrom-JsonResponse $resp 'Sign-in'
        $type = $result.responseStatus.type

        # 2) Optional: multi-factor authentication
        if ($type -eq 'MFA_REQUIRED') {
            $mfaMethod = 'email'
            if ($result.PSObject.Properties['customerMfaInfo'] -and $result.customerMfaInfo.mfaLastMethodUsed) {
                $mfaMethod = $result.customerMfaInfo.mfaLastMethodUsed
            }
            $code = Read-Host "Enter MFA code (sent via $mfaMethod)"
            $mfaBody = @{
                mfaMethod           = $mfaMethod
                mfaVerificationCode = $code.Trim()
                rememberMyBrowser   = $true
                reconsentList       = @()
                mfaSetup            = $false
            } | ConvertTo-Json -Compress
            $resp = Invoke-WebRequest @request -Uri "$SsoBase/mobile/api/mfa/verifyCode?$query" -Body $mfaBody
            $result = ConvertFrom-JsonResponse $resp 'MFA verification'
            $type = $result.responseStatus.type
        }

        switch ($type) {
            'SUCCESSFUL' { return $result.serviceTicketId }
            'INVALID_USERNAME_PASSWORD' {
                throw ("Garmin rejected the e-mail/password combination.`n" +
                    "  - Check upper/lower case and keyboard layout (Y/Z), and use the e-mail address, not the display name.`n" +
                    "  - If you sign in with Google/Apple/Facebook, you have no Garmin password: set one via 'Forgot password'.`n" +
                    "  - Repeated failures can lock the account.")
            }
            'CAPTCHA_REQUIRED' { throw 'Garmin requires a CAPTCHA for this sign-in. Sign in once at https://connect.garmin.com in a browser, then try again later.' }
            default { throw "Sign-in failed: HTTP $([int]$resp.StatusCode), responseStatus '$type'." }
        }
    }

    function Get-DiToken([string]$Ticket) {
        # Exchange the service ticket; Garmin accepts different client IDs over time, so try each
        foreach ($clientId in $DiClientIds) {
            $resp = Invoke-WebRequest -Method Post -Uri $DiTokenUrl -SkipHttpErrorCheck `
                -Headers (Get-NativeHeaders @{ Authorization = (Get-BasicAuth $clientId); Accept = 'application/json'; 'Cache-Control' = 'no-cache' }) `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body @{ client_id = $clientId; service_ticket = $Ticket; grant_type = $DiGrantType; service_url = $IosServiceUrl }

            if ([int]$resp.StatusCode -eq 429) { throw 'DI token exchange was rate limited (HTTP 429).' }
            if ([int]$resp.StatusCode -ne 200) {
                Write-Verbose "DI exchange failed for ${clientId}: HTTP $([int]$resp.StatusCode)"
                continue
            }
            $data = $resp.Content | ConvertFrom-Json
            return New-TokenStore $data.access_token $data.refresh_token $clientId
        }
        throw 'DI token exchange failed for all client IDs.'
    }

    function Update-DiToken($Store) {
        if (-not $Store.di_refresh_token -or -not $Store.di_client_id) { throw 'The token file contains no refresh token. Sign in without -Refresh.' }

        $resp = Invoke-WebRequest -Method Post -Uri $DiTokenUrl -SkipHttpErrorCheck `
            -Headers (Get-NativeHeaders @{ Authorization = (Get-BasicAuth $Store.di_client_id); Accept = 'application/json'; 'Cache-Control' = 'no-cache' }) `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{ grant_type = 'refresh_token'; client_id = $Store.di_client_id; refresh_token = $Store.di_refresh_token }

        if ([int]$resp.StatusCode -ne 200) {
            throw "Token refresh failed (HTTP $([int]$resp.StatusCode)). The refresh token may have expired - sign in without -Refresh."
        }
        $data = $resp.Content | ConvertFrom-Json
        $refreshToken = if ($data.PSObject.Properties['refresh_token'] -and $data.refresh_token) { $data.refresh_token } else { $Store.di_refresh_token }
        New-TokenStore $data.access_token $refreshToken $Store.di_client_id
    }

    function New-TokenStore([string]$AccessToken, [string]$RefreshToken, [string]$FallbackClientId) {
        # Same structure as garminconnect's dumps(); the client ID is taken from the JWT when present
        $clientId = $FallbackClientId
        $payload = ConvertFrom-JwtPayload $AccessToken
        if ($payload -and $payload.PSObject.Properties['client_id'] -and $payload.client_id) { $clientId = [string]$payload.client_id }
        [pscustomobject][ordered]@{
            di_token         = $AccessToken
            di_refresh_token = $RefreshToken
            di_client_id     = $clientId
        }
    }

    #endregion

    #region Main

    if ($Refresh) {
        if (-not (Test-Path $TokenFile)) { throw "No stored tokens at '$TokenFile'. Sign in without -Refresh first." }
        Write-Host 'Renewing access token with the stored refresh token...' -ForegroundColor Cyan
        $store = Update-DiToken (Get-Content $TokenFile -Raw | ConvertFrom-Json)
    }
    else {
        $cred = Get-Credential -Message 'Garmin Connect sign-in (e-mail and password)'
        if (-not $cred) { throw 'Cancelled.' }
        Write-Host 'Signing in to Garmin SSO...' -ForegroundColor Cyan
        $ticket = Invoke-GarminMobileLogin $cred
        Write-Host 'Exchanging service ticket for DI token...' -ForegroundColor Cyan
        $store = Get-DiToken $ticket
    }

    # Save (UTF-8 without BOM, compatible with garminconnect)
    $dir = Split-Path $TokenFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $store | ConvertTo-Json -Compress | Set-Content -Path $TokenFile -Encoding utf8NoBOM

    $payload = ConvertFrom-JwtPayload $store.di_token
    $expiresAt = if ($payload -and $payload.PSObject.Properties['exp']) { [DateTimeOffset]::FromUnixTimeSeconds([long]$payload.exp).LocalDateTime } else { $null }

    Write-Host "Token created and saved to: $TokenFile" -ForegroundColor Green
    if ($expiresAt) { Write-Host "Access token valid until: $expiresAt" }

    if ($Test) {
        $me = Invoke-RestMethod -Uri 'https://connectapi.garmin.com/userprofile-service/socialProfile' `
            -Headers (Get-NativeHeaders @{ Authorization = "Bearer $($store.di_token)"; Accept = 'application/json' })
        Write-Host "Test succeeded - signed in as: $($me.displayName) ($($me.fullName))" -ForegroundColor Green
    }

    [pscustomobject]@{
        AccessToken = $store.di_token
        ClientId    = $store.di_client_id
        ExpiresAt   = $expiresAt
    }

    #endregion
}