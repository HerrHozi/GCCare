<#
.SYNOPSIS
Starts a Garmin Connect login session through the bundled Python script.

.DESCRIPTION
New-GarminConnectSession executes Corefunctions\connectToGarmin.py to create
or refresh a Garmin Connect session. The Python script can restore saved tokens
or prompt for credentials and MFA when needed.

If Email, SecurePassword, or TokenStore are provided, they are passed via
environment variables for the duration of this function call only.

.PARAMETER Email
Optional Garmin account email address. If omitted, the Python script prompts
for the email when no reusable tokens are available.

.PARAMETER SecurePassword
Optional Garmin account password as SecureString. If omitted, the Python script
prompts for the password when no reusable tokens are available.

.PARAMETER TokenStore
Optional path to the Garmin token store directory. If omitted, the Python script
uses its default token store location.

.PARAMETER EnableLogging
Optional switch to enable additional logging (project-dependent).

.EXAMPLE
PS> New-GarminConnectSession

Runs the Python login script and uses interactive prompts if required.

.EXAMPLE
PS> $cred = Get-Credential
PS> New-GarminConnectSession -Email $cred.UserName -SecurePassword $cred.Password

Runs the Python login script with provided credentials.

.EXAMPLE
PS> New-GarminConnectSession -TokenStore 'C:\Temp\.garminconnect'

Runs the Python login script and uses the specified token store directory.
#>
Function New-GarminConnectSession {

    [Alias('Connect-GC')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Email,
        [securestring]$SecurePassword,
        [string]$TokenStore,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Starting Garmin Connect session ..."

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

    $previousEmail = [Environment]::GetEnvironmentVariable('EMAIL', 'Process')
    $previousPassword = [Environment]::GetEnvironmentVariable('PASSWORD', 'Process')
    $previousTokenStore = [Environment]::GetEnvironmentVariable('GARMINTOKENS', 'Process')

    try {
        if ($PSBoundParameters.ContainsKey('Email') -and -not [string]::IsNullOrWhiteSpace($Email)) {
            [Environment]::SetEnvironmentVariable('EMAIL', $Email, 'Process')
        }

        if ($PSBoundParameters.ContainsKey('SecurePassword') -and $null -ne $SecurePassword) {
            $passwordBstr = [System.IntPtr]::Zero
            try {
                $passwordBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
                $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)
                [Environment]::SetEnvironmentVariable('PASSWORD', $plainPassword, 'Process')
            }
            finally {
                if ($passwordBstr -ne [System.IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr)
                }
                Remove-Variable -Name plainPassword -ErrorAction SilentlyContinue
            }
        }

        if ($PSBoundParameters.ContainsKey('TokenStore') -and -not [string]::IsNullOrWhiteSpace($TokenStore)) {
            $resolvedTokenStore = [System.IO.Path]::GetFullPath($TokenStore)
            [Environment]::SetEnvironmentVariable('GARMINTOKENS', $resolvedTokenStore, 'Process')
            Invoke-Output -Type Info -Message "Token store: $resolvedTokenStore" -NoExtraLines
        }

        Invoke-Output -Type Info -Message "Python command: $pythonCommand" -NoExtraLines
        & $pythonCommand $pythonScriptPath

        if ($LASTEXITCODE -ne 0) {
            throw "Python script failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('EMAIL', $previousEmail, 'Process')
        [Environment]::SetEnvironmentVariable('PASSWORD', $previousPassword, 'Process')
        [Environment]::SetEnvironmentVariable('GARMINTOKENS', $previousTokenStore, 'Process')
    }

    Invoke-Output -Type Success -Message "Garmin Connect session completed successfully."
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

}
