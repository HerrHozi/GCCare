<#
.SYNOPSIS
Logs function start and end information and measures its runtime.

.DESCRIPTION
Use Begin at the start of a function to log its name and capture timing details.
Pass the returned object to End to log the elapsed runtime and function name.

.PARAMETER StartRunTime
Currently unused. End reads the start timestamp from Details.StartRunTime.

.PARAMETER Begin
Logs the calling function's name and returns an object containing its start
timestamp and function name. StackNumber controls which call-stack frame is used.

.PARAMETER End
Calculates and logs the elapsed runtime. Use with Details returned by Begin.

.PARAMETER StackNumber
Call-stack frame used to determine the function name when Begin is specified.
Defaults to 2, which identifies the calling function.

.PARAMETER Details
Object returned by Begin, containing StartRunTime and FunctionName properties.
Required when End is specified.

.OUTPUTS
System.Management.Automation.PSCustomObject. With Begin, returns StartRunTime
and FunctionName properties. With End, writes log entries and returns no output.

.EXAMPLE
$details = Measure-FunctionRuntime-Begin
Captures the calling function's name and start timestamp.

.EXAMPLE
Measure-FunctionRuntime-End -Details $details
Logs the elapsed runtime for the function captured by the Begin call.

.NOTES


.FUNCTIONALITY
Logs function start and end information and measures elapsed runtime.

.COMPONENT
Category: Sub Function

#>
function Measure-FunctionRuntime {

    Param(
        [string]$StartRunTime,
        [Switch]$Begin,
        [Switch]$End,
        [int]$StackNumber = 2,     #StackNumber 2 must be used to get the calling parent function's name.
        [pscustomobject[]]$Details
    )

    If ($Begin) {
        
        $ParentFunction = Get-FunctionName -StackNumber $StackNumber
        Write-Log -Message "### Start Function $ParentFunction ###"
        $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
        
        return [pscustomobject]@{
            StartRunTime = $StartRunTime
            FunctionName = $ParentFunction
        }
    }

    If ($End) {
        $runtime = Get-RunTime -StartRunTime $($Details.StartRunTime)
        Write-Log -Message "    Run Time: $runtime [h] ###"
        Write-Log -Message "### End Function $($Details.FunctionName) ###"
    }
}