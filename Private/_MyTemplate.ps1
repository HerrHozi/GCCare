function _MyTemplate {

    ################################################################################
    #####                                                                      ##### 
    #####    Description                ######                                 
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

    #<neuer code>
    # @{N = 'whencreated'; E = { Convert-FromUnixTime -seconds $_.whencreated -objectType 'User' -type 'whencreated' } }


    invoke-output 

    Write-Log -Message "    >> using "
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $true
}



