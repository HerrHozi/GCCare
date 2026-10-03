function Invoke-WingetInstall {
    <#
    .SYNOPSIS
        Installs a package via winget and returns the exit code.

    .DESCRIPTION
        Wraps winget install with standard flags for non-interactive, silent
        installation. Accepts package agreements automatically.

    .PARAMETER PackageId
        The winget package identifier (e.g., 'Mozilla.Firefox').

    .PARAMETER Scope
        Installation scope. Defaults to 'user'. Use 'machine' for system-wide
        installs (requires admin).

    .EXAMPLE
        Invoke-WingetInstall -PackageId 'Mozilla.Firefox'

    .EXAMPLE
        Invoke-WingetInstall -PackageId 'Microsoft.AzureCLI' -Scope 'machine'

    .OUTPUTS
        System.Int32. The winget process exit code. 0 indicates success.

    .NOTES
        Caller is responsible for checking the return value. All installs are
        pinned to --source winget to avoid certificate failures on the msstore
        source.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter()]
        [ValidateSet('user', 'machine')]
        [string]$Scope = 'user'
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $wingetArgs = @(
        'install'
        '--id', $PackageId
        '--source', 'winget'
        '--scope', $Scope
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
        '--silent'
    )

    $captureFile = Join-Path -Path $env:TEMP -ChildPath ("djm-winget-install-{0}.log" -f [Guid]::NewGuid())
    try {
        & winget @wingetArgs *> $captureFile
        $exitCode = $LASTEXITCODE
        Add-LogFileContent -Header "winget install $PackageId (scope=$Scope, exit=$exitCode)" -FilePath $captureFile
    } finally {
        Remove-Item -Path $captureFile -Force -ErrorAction SilentlyContinue
    }

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $exitCode
}