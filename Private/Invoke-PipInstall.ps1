function Invoke-PipInstall {
    <#
    .SYNOPSIS
        Installs a Python package via pip and returns the exit code.

    .DESCRIPTION
        Wraps pip install with --user flag for user-scoped installation.

    .PARAMETER PackageName
        The PyPI package name (e.g., 'roadrecon').

    .EXAMPLE
        Invoke-PipInstall -PackageName 'roadrecon'

    .OUTPUTS
        System.Int32. The pip process exit code. 0 indicates success.

    .NOTES
        Requires Python to already be installed and on PATH.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName
    )

    $captureFile = Join-Path -Path $env:TEMP -ChildPath ("gccare-pip-install-{0}.log" -f [Guid]::NewGuid())
    try {
        python -m pip install --user $PackageName *> $captureFile
        $exitCode = $LASTEXITCODE
        Write-Log -Message "    >> pip install $PackageName (exit=$exitCode)"
        return $exitCode
    }
    finally {
        Remove-Item -Path $captureFile -Force -ErrorAction SilentlyContinue
    }
}