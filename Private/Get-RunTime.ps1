function Get-RunTime {

    ################################################################################
    #####                                                                      ##### 
    #####    Get the run time of each function, to improve the execution       #####                     
    #####                                                                      #####
    ################################################################################

    param (
        [datetime] $StartRunTime
    )
   
    [datetime] $EndRunTime = (Get-Date).ToString($Script:DateFormatLog)
    $RunTime = NEW-TIMESPAN -Start $StartRunTime -End $EndRunTime
    return $RunTime
}
