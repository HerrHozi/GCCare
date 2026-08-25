function Show-DecisionPrompt {
    
    ################################################################################
    #####                                                                      ##### 
    #####    Show a custom Choice                                              #####             
    #####                                                                      #####
    ################################################################################

    param(
        [string]$Title = "Ready to proceed with this step?",
        [string]$Message = "Please select an option:",
        [object[]]$Options = @(
            [pscustomobject] @{ 
                Label = "&Yes"
                Help  = 'Continue with this step'
                Value = $Script:Yes 
            },
            [pscustomobject] @{ 
                Label = "&No"
                Help  = 'Skip this step'
                Value = $Script:No 
            }
        ),
        [int]$Default = 0
    )
    
    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    If ($title.StartsWith("REPEAT |")) {
        [int]$total = 64
        $text = " $title "
        $chars = [int](($total - $text.Length) / 2)
        $separator = ':' * $chars
        $title = "$separator $text $separator"
    }
    
    $values = @()
    $choices = @()
    foreach ($opt in $Options) {
        If ($null -ne $opt.help) {
            $values += $opt.value
            $choices += New-Object System.Management.Automation.Host.ChoiceDescription "$($opt.label)", "$($opt.help)"
        }
    }

    Write-host "`n`n[>] $Title" -ForegroundColor $Script:FGCDecisionPrompt
    $result = $Host.UI.PromptForChoice('', $Message, $choices, $Default)

    Write-Log -Message "    >> $Title - User selected option: $( $values[$result])"
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"
    
    return $values[$result]
}