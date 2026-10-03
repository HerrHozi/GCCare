function Invoke-GCCareDirectory {

    ################################################################################
    #####                                                                      ##### 
    #####    Creates the log directory if it does not exist.                   #####                
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param (
        [String]$Directory
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    if (-not (Test-Path $Directory)) {
        try {
            New-Item -Path $Directory -ItemType Directory -Force -ErrorAction Stop
            Write-Log -Message "Invoke-GCCareDirectory    >> Log directory created: $Directory"
        }
        catch {
            Invoke-Output -Message "Failed to create log directory: $Directory. Error: $($_.Exception.Message)" -Type Error
            Write-Error "Failed to create $Directory`: $($_.Exception.Message)"
            throw
            return
        }
    }
    else {
        Write-Log -Message "Invoke-GCCareDirectory:    >> Log directory already exists: $Directory"
    }

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"
}


