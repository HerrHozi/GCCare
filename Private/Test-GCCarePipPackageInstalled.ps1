function Test-GCCarePipPackageInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,
        [string]$PythonCommand = 'python'
    )

    try {
        & $PythonCommand -m pip show $PackageName *> $null
        $result = ($LASTEXITCODE -eq 0)
    }
    catch {
        $result = $false
    }

    If ($result -eq $false) {
        Invoke-Output -Type Missing -Message "Package '$PackageName' is not installed. Please install it using 'pip install $PackageName'." -NoExtraLines
    }
    else {
        $output = & $PythonCommand -m pip show $PackageName 2>&1
        $version = ($output -match '^Version:') -replace '^Version:\s*'
        Invoke-Output -Type Success -Message "Package '$PackageName' is installed. | Version: $version" -NoExtraLines
    }
}
