function Save-GarminTokenStore {
    # Writes the token store encrypted with Windows DPAPI: first CurrentUser, then LocalMachine.
    # Decryption needs both this user AND this computer, so a copied file is useless elsewhere.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Store
    )

    $entropy = [Text.Encoding]::UTF8.GetBytes('GCCare-GarminToken-v1')
    $plain = [Text.Encoding]::UTF8.GetBytes(($Store | ConvertTo-Json -Compress))
    $userLayer = [Security.Cryptography.ProtectedData]::Protect($plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $machineLayer = [Security.Cryptography.ProtectedData]::Protect($userLayer, $entropy, [Security.Cryptography.DataProtectionScope]::LocalMachine)

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir
    }
    Set-Content -LiteralPath $Path -Value ([Convert]::ToBase64String($machineLayer)) -Encoding utf8NoBOM
}
