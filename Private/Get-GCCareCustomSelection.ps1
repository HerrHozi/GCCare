function Get-GCCareCustomSelection {

    ################################################################################
    #####                                                                      #####
    #####    Returns the Where-Object / Select-Object values of a selection    #####
    #####    GCCare.json > GarminConnectApi > CustomSelection > <Section>      #####
    #####    > <Name> (fallback: <DefaultName>)                                #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Badge', 'Activity')]
        [string]$Section,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$DefaultName,
        [string]$ConfigFile = $Script:ConfigFile
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $selection = $null
    $usedName = $Name
    try {
        $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
        $sectionNode = $config.GarminConnectApi.CustomSelection.$Section
        $selection = $sectionNode.$Name
        if (-not $selection -and $DefaultName) {
            $usedName = $DefaultName
            $selection = $sectionNode.$DefaultName
        }
    }
    catch {
        Invoke-Output -Type Warning -Message "Could not read the custom selection from '$ConfigFile': $($_.Exception.Message)"
    }

    if ($selection) {
        Write-Log -Message "    >> Custom selection '$Section > $usedName' loaded from $ConfigFile"
    }
    else {
        Invoke-Output -Type Warning -Message "No custom selection '$Name' in '$ConfigFile' (GarminConnectApi > CustomSelection > $Section > $Name)."
    }

    # "{$_.earnedByMe -eq $False}" or "$_.earnedByMe -eq $False" -> script block; empty -> no filter
    $filterText = ([string]$selection.'Where-Object').Trim()
    if ($filterText.StartsWith('{') -and $filterText.EndsWith('}')) {
        $filterText = $filterText.Substring(1, $filterText.Length - 2).Trim()
    }

    # "badgeName, badgeKey" -> @('badgeName', 'badgeKey'); empty -> all properties
    $properties = @(([string]$selection.'Select-Object').Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $result = [pscustomobject]@{
        Name     = $usedName
        Filter   = if ($filterText) { [scriptblock]::Create($filterText) } else { $null }
        Property = $properties
    }

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
