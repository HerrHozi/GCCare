function Invoke-Output {

    ################################################################################
    #####                                                                      ##### 
    #####    Customize Output based on Type and Message                        #####                                
    #####                                                                      #####
    ################################################################################
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [Alias('T')]
        [ValidateSet("Info", "Input", "Success", "Missing", "Warning", "Error", "CodeSnippet", "TextMaker", "Header", "Bullet", "Quit", "H1")]
        [string] $Type = "Info",
        [Parameter(Mandatory = $false, Position = 1)]
        [Alias('M')]
        [string] $Message,
        [Parameter(Mandatory = $false, Position = 2)]
        [Alias('TM')]
        [string] $TextMaker = "",
        [switch] $NoExtraLines
    )

    $CurrentFunction = Get-FunctionName
    #Write-Log -Message "### Start Function $CurrentFunction ###"
    #$StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    switch ($Type) {
        "Header" { 
            $width = 70
            $line = '_' * $width
            $padding = [math]::Max(0, [math]::Floor(($width - $Message.Length) / 2))
            $UpdatedText = ("{0}{1}" -f (' ' * $padding), $Message)
    
            Write-Host `n$line`n
            Write-Host $UpdatedText
            Write-Host $line`n
            $level = "INFO"
            $Message = "`n$line`n`n$UpdatedText`n$line`n"
        }
        "CodeSnippet" { 
            Write-Host "`n  [>] $Message`n"           -ForegroundColor $Script:FGCCommand 
            $level = "INFO"
        }
        "Warning" { 
            $warn = [char]0x26A0
            Write-Host "`n  [$warn] WARNING: $Message`n`n"  -ForegroundColor $Script:FGCWarning
            #Write-Host "`n  [!] WARNING: $Message`n`n"  -ForegroundColor $Script:FGCWarning
            $level = "WARN" 
        }
        "Bullet" { 
            Write-host "  • $Message " -ForegroundColor $Script:FGCSInfo -NoNewline
            Write-host "$TextMaker" -ForegroundColor $Script:FGCMInfo
            $level = "INFO"
        }
        "Success" {
            If ($NoExtraLines) {
                Write-host "  [✅] $Message" # -ForegroundColor $Script:FGCWarning 
            }
            Else {
                Write-host "`n  [✅] $Message`n`n" # -ForegroundColor $Script:FGCWarning 
            }   

            #Write-Host "`n  [✓] $Message`n`n" -ForegroundColor DarkGreen
            $level = "INFO"
        }
        "Missing" {
            If ($NoExtraLines) {
                Write-host "  [❌] $Message" -ForegroundColor $Script:FGCSInfo -NoNewline
                Write-host "$TextMaker" -ForegroundColor $Script:FGCMInfo # -ForegroundColor $Script:FGCWarning 
            }
            Else {
                Write-host "`n  [❌] $Message" -ForegroundColor $Script:FGCSInfo -NoNewline
                Write-host "$TextMaker`n`n" -ForegroundColor $Script:FGCMInfo # -ForegroundColor $Script:FGCWarning 
            }   

            #Write-Host "`n  [✓] $Message`n`n" -ForegroundColor DarkGreen
            $level = "WARN"
        }
        "Info" {
            If ($NoExtraLines) {
                Write-host "  [i] $Message"  -ForegroundColor $Script:FGCSInfo
            }
            Else { 
                Write-Host "`n  [i] $Message`n`n" -ForegroundColor $Script:FGCSInfo
            } 
            $level = "INFO"
        }
        "TextMaker" { 
            Write-host "`n  [i] $Message " -ForegroundColor $Script:FGCSInfo -NoNewline
            Write-host "$TextMaker`n`n" -ForegroundColor $Script:FGCMInfo
            $level = "INFO"
        }
        "Input" { 
            Write-Host "`n  [~] $Message"           -ForegroundColor $Script:FGCInput -NoNewLine
            $answer = Read-Host ":"  
            Write-Host "`n"
            $level = "INFO"
        }
        "Quit" { 
            Write-Host "`n  [~] $Message`n`n"           -ForegroundColor $Script:FGCInput
            $level = "INFO"
        }
        "Error" { 
            Write-Host "`n  [X] ERROR: $Message`n`n"    -ForegroundColor $Script:FGCError
            $level = "ERROR"
        }
        "H1" { 
            Write-Host "$Message"    -ForegroundColor $Script:FGCWarning
            $level = "INFO"
        }
        default { 
            Write-Host "`n  [i] $Message`n`n"           -ForegroundColor $Script:FGCSInfo
            $level = "INFO" 
        }
    }

    #[ValidateSet("INFO", "WARN", "ERROR", "FATAL", "DEBUG")]
    Write-Log -Message "### $CurrentFunction >> $Type | $Message $TextMaker" -Level $level

    ######################## main code ############################
    #$runtime = Get-RunTime -StartRunTime $StartRunTime
    #Write-Log -Message "    Run Time: $runtime [h] ###"
    #Write-Log -Message "### End Function $CurrentFunction ###"

    If ($Type -eq "Input") {
        return $answer
    }

}
