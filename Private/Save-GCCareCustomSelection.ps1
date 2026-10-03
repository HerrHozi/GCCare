function Save-GCCareCustomSelection {

    ################################################################################
    #####                                                                      #####
    #####    Saves the Where-Object / Select-Object values of a selection      #####
    #####    GCCare.json > GarminConnectApi > CustomSelection > <Section>      #####
    #####    > <Name> (only the passed values are changed)                     #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Badge', 'Activity')]
        [string]$Section,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [scriptblock]$Filter,
        [string[]]$Property,
        [string]$ConfigFile = $Script:ConfigFile
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json

    # Create missing sections: GarminConnectApi > CustomSelection > <Section> > <Name>
    $node = $config
    foreach ($key in 'GarminConnectApi', 'CustomSelection', $Section, $Name) {
        if (-not $node.PSObject.Properties[$key]) {
            $node | Add-Member -MemberType NoteProperty -Name $key -Value ([pscustomobject]@{})
        }
        $node = $node.$key
    }

    # Same notation as in the original query: "{...}" and "a, b, c"
    if ($PSBoundParameters.ContainsKey('Filter')) {
        $node | Add-Member -MemberType NoteProperty -Name 'Where-Object' -Value "{$($Filter.ToString().Trim())}" -Force
    }
    if ($PSBoundParameters.ContainsKey('Property')) {
        $node | Add-Member -MemberType NoteProperty -Name 'Select-Object' -Value (($Property | ForEach-Object { $_.Trim() }) -join ', ') -Force
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ConfigFile -Encoding utf8NoBOM
    Write-Log -Message "    >> Custom selection '$Section > $Name' saved to $ConfigFile"
    Invoke-Output -Type Info -Message "Custom selection '$Section > $Name' saved to $ConfigFile" -NoExtraLines

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"
}
