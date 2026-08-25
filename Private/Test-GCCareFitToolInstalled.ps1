function Test-GCCareFitToolInstalled {

    ################################################################################
    #####                                                                      ##### 
    #####    Description: Prüft zuverlässig, ob das FitTool installiert ist    #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Checking Python installation ..."

    $pythonCandidates = @(
        @{ Name = 'python'; Args = @('--version') }
        @{ Name = 'python3'; Args = @('--version') }
        @{ Name = 'py'; Args = @('-V') }
    )

    $pythonInfo = $null

    foreach ($candidate in $pythonCandidates) {
        $cmdName = $candidate.Name
        $cmdArgs = $candidate.Args

        $commandResult = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
        if (-not $commandResult) { continue }

        $cmdPath = $commandResult.Source
        if ([string]::IsNullOrWhiteSpace($cmdPath)) { $cmdPath = $commandResult.Path }
        if ([string]::IsNullOrWhiteSpace($cmdPath)) { $cmdPath = $commandResult.Definition }

        # Windows Store Alias ignorieren (kein echtes Python)
        if ($cmdPath -and ($cmdPath -match '\\WindowsApps\\')) {
            continue
        }

        try {
            $versionOutput = & $cmdName @cmdArgs 2>&1
            $versionText = ($versionOutput | Out-String).Trim()

            if ($versionText -match '^Python\s+\d+(\.\d+){1,3}\b') {
                $pythonInfo = [PSCustomObject]@{
                    IsInstalled = $true
                    Command     = $cmdName
                    Path        = $cmdPath
                    Version     = $versionText
                }
                break
            }
        }
        catch {
            continue
        }
    }

    if (-not $pythonInfo) {
        $pythonInfo = [PSCustomObject]@{
            IsInstalled = $false
            Command     = $null
            Path        = $null
            Version     = $null
        }
    }

    if (-not $Quiet) {

        if ($pythonInfo.IsInstalled) {

            Invoke-Output -Type Bullet -Message "Version:" -TextMaker "$($pythonInfo.Version)" -NoExtraLines
            Invoke-Output -Type Bullet -Message "Command:" -TextMaker "$($pythonInfo.Command)" -NoExtraLines
            Invoke-Output -Type Bullet -Message "Path:   " -TextMaker "$($pythonInfo.Path)" -NoExtraLines
            Invoke-Output -Type Success "Python is installed."
        }
        else {
            Invoke-Output -Type Error "Python is not installed."
            Invoke-Output -Type CodeSnippet -Message "Install Python from https://www.python.org/downloads/windows/"
            $answer = Show-DecisionPrompt -Title "REPEAT | Python is not installed" -Message "Do you want to install Python 3.13 via winget?" -Options @(
                [pscustomobject] @{ 
                    Label = "&Yes"
                    Help  = 'Install Python 3.13 via winget'
                    Value = $Script:Yes 
                },
                [pscustomobject] @{ 
                    Label = "&No"
                    Help  = 'Skip this step'
                    Value = $Script:No 
                }
            ) -Default 0
                
            if ($answer -eq $Script:Yes) {
                Invoke-Output -Type Info "Installing Python 3.13 via winget..."
                $exitCode = Invoke-WingetInstall -PackageId 'Python.Python.3.13'
                $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'Process')
            }
        }
    }
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    #return $pythonInfo
}



