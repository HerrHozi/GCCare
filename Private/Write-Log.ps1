Function Write-Log {

    ################################################################################
    #####                                                                      ##### 
    #####    log all actions into a log file                                   #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False)]
        [ValidateSet("INFO", "WARN", "ERROR", "FATAL", "DEBUG")]
        [String]
        $Level = "INFO",

        [Parameter(Mandatory = $True)]
        [string]
        $Message,

        [Parameter(Mandatory = $False)]
        [string]
        $logfile = $Script:ASModuleLog
    )

    If ($EnableLogging -ne $true) { return }
    $Stamp = (Get-Date).ToUniversalTime().ToString($Script:DateFormatLog)
    
    $Line = "$Stamp $Level $Message"
    If ($logfile) {
        Add-Content $logfile -Value $Line
    }
    Else {
        Write-Output $Line
    }
}
