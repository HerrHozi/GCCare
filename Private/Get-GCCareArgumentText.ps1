function Get-GCCareArgumentText {

    ################################################################################
    #####                                                                      #####
    #####    Returns the argument text as typed by the user per parameter      #####
    #####    (e.g. '3,05' for -BoneMass 3,05, which PowerShell binds as 3, 5)  #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.InvocationInfo]$Invocation
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $result = @{}
    $commandParameters = $Invocation.MyCommand.Parameters
    $commandNames = @($Invocation.MyCommand.Name) + @($Invocation.InvocationName)

    if ($Invocation.Line) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Invocation.Line, [ref]$null, [ref]$null)
        $commandAst = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in $commandNames
            }, $true) |
            Sort-Object -Property { [math]::Abs($_.Extent.StartColumnNumber - $Invocation.OffsetInLine) } |
            Select-Object -First 1

        if ($commandAst) {
            $positionalNames = @($commandParameters.Values |
                    Where-Object { -not $_.SwitchParameter } |
                    ForEach-Object { $p = $_; $p.ParameterSets.Values | Where-Object { $_.Position -ge 0 } | ForEach-Object { [pscustomobject]@{ Name = $p.Name; Position = $_.Position } } } |
                    Sort-Object -Property Position -Unique |
                    ForEach-Object { $_.Name })
            $positionIndex = 0
            $elements = @($commandAst.CommandElements | Select-Object -Skip 1)

            for ($i = 0; $i -lt $elements.Count; $i++) {
                $element = $elements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    # Resolve abbreviations like -Bone -> BoneMass
                    $name = @($commandParameters.Keys | Where-Object { $_ -like "$($element.ParameterName)*" })
                    if ($name.Count -ne 1) { continue }
                    $parameter = $commandParameters[$name[0]]
                    if ($element.Argument) {
                        $result[$parameter.Name] = $element.Argument.Extent.Text
                    }
                    elseif (-not $parameter.SwitchParameter -and $i + 1 -lt $elements.Count) {
                        $i++
                        $result[$parameter.Name] = $elements[$i].Extent.Text
                    }
                }
                elseif ($positionIndex -lt $positionalNames.Count) {
                    $result[$positionalNames[$positionIndex]] = $element.Extent.Text
                    $positionIndex++
                }
            }
        }
    }

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
