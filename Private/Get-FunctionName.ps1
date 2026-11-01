<#
.SYNOPSIS
Returns a function name from the PowerShell call stack.

.DESCRIPTION
Reads the FunctionName property from the call-stack frame at the selected index.
The zero-based default index 1 returns the direct caller; index 0 is this function.

.PARAMETER StackNumber
Zero-based call-stack index to read. Defaults to 1.

.INPUTS
None. Pipeline input is not supported.

.OUTPUTS
System.String. The function name stored in the selected call-stack frame.

.EXAMPLE
function Test-Caller { Get-FunctionName }
Test-Caller
Returns: Test-Caller

.EXAMPLE
Get-FunctionName -StackNumber 0
Returns: Get-FunctionName

.FUNCTIONALITY
Returns the function name from the selected call-stack entry.

.COMPONENT
Category: Sub Function
#>
function Get-FunctionName {
    param(
        [int]$StackNumber = 1
    )

    $CallStack = Get-PSCallStack
    return [string]$CallStack[$StackNumber].FunctionName
}
