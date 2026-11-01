function Read-GarminTokenStore {
    # Reads the DPAPI-encrypted token store (see Save-GarminTokenStore).
    # A legacy plain-text JSON file is still accepted and is encrypted on the next save.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $text = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    if ($text.StartsWith('{')) {
        return $text | ConvertFrom-Json
    }

    $entropy = [Text.Encoding]::UTF8.GetBytes('GCCare-GarminToken-v1')
    try {
        $machineLayer = [Convert]::FromBase64String($text)
        $userLayer = [Security.Cryptography.ProtectedData]::Unprotect($machineLayer, $entropy, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($userLayer, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }
    catch {
        throw "The Garmin token file '$Path' cannot be decrypted. It can only be read by the user and on the computer that created it. Sign in again with Get-GarminToken. ($($_.Exception.Message))"
    }
    return [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
}
