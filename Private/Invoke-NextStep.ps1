
function Invoke-NextStep {

    ################################################################################
    #####                                                                      ##### 
    #####    Press Enter to continue                              
    #####                                                                      #####
    ################################################################################

    Param([string] $param1, [string] $param2)

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Write-Host "`n`n  [i] Press Enter to continue ... " -ForegroundColor $Script:FGCQuestion -NoNewline; [void][Console]::ReadLine()

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"
}