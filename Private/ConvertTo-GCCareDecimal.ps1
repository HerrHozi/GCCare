function ConvertTo-GCCareDecimal {

    ################################################################################
    #####                                                                      #####
    #####    Converts a number entered with '.' or ',' as decimal separator    #####
    #####    (3.4, '3,4' or 3,4 -> 3.4)                                        #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        # Argument text as typed (see Get-GCCareArgumentText); preferred over the bound value
        [string]$ArgumentText
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    $text = $null
    if ($ArgumentText -and $ArgumentText -notmatch '^[\$\(@]') {
        # Literal as typed: 3,05 / '3,05' / "3.05"
        $text = $ArgumentText.Trim().Trim("'", '"')
    }
    elseif ($Value -is [string]) {
        $text = $Value
    }
    elseif ($Value -is [array]) {
        # Unquoted 3,4 is bound as @(3, 4); leading zeros of the decimals are lost (3,05 -> 3, 5)
        if ($Value.Count -ne 2) { throw "Invalid number for -$Name : '$($Value -join ',')'." }
        $text = '{0}.{1}' -f $Value[0], $Value[1]
        Invoke-Output -Type Warning -Message "-$Name $($Value -join ',') was read as $text. Use '.' or quotes ('$($Value -join ',')') to be safe." -NoExtraLines
    }
    elseif ($null -ne $Value) {
        $text = ([double]$Value).ToString([Globalization.CultureInfo]::InvariantCulture)
    }

    if ($text -match '\..*,|,.*\.') {
        throw "Invalid number for -$Name : '$text' (use either '.' or ',' as decimal separator, no thousands separator)."
    }

    $number = 0.0
    if (-not [double]::TryParse(($text -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        throw "Invalid number for -$Name : '$text'."
    }
    Write-Log -Message "    >> -$Name '$text' -> $number"

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $number
}
