function Write-HighlightedCode {
    param(
        [string]$Code
    )
    try {
        $CurrentFunction = Get-FunctionName
        Write-Log -Message "### Start Function $CurrentFunction ###"
        $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
        #################### main code | out- host #####################
    }
    catch {
        <#Do this if a terminating exception happens#>
    }


    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)
    
    $totalPos = 0
    
    foreach ($token in $tokens) {
        # Sicherer Pre-Text
        $preLen = [Math]::Max(0, $token.Extent.StartOffset - $totalPos)
        if ($preLen -gt 0 -and $totalPos + $preLen -le $Code.Length) {
            $preText = $Code.Substring($totalPos, $preLen)
            Write-Host $preText -NoNewline -ForegroundColor Gray
        }
        
        # Token farbig
        $color = if ($token.Text -match '^(MATCH|RETURN|SET|REMOVE|WITH|WHERE|NOT|IN|AND|OR|AS|LIMIT|ORDER|BY|SKIP|OPTIONAL|CALL|YIELD|MERGE|CREATE|DELETE|DETACH|UNWIND|FOREACH|UNION)$') {
            'Magenta'
        }
        elseif ($token.Text -match '^(true|false)$|:(true|false)$') {
            'Cyan'
        }
        elseif ($token.Text -match "='[^']*'$") {
            'Green'
        }
        else {
            switch -Regex ($token.Kind) {
                'Identifier' { If ($token.TokenFlags -eq 'CommandName') { 'Yellow' } else { 'White' }; break }
                'Generic|Command' { If ($token.TokenFlags -eq 'CommandName') { 'Yellow' } else { 'White' }; break }
                'String|HereString' { 'Green' }
                'If|Else|For|Foreach|Function|While|Do|Until' { 'Cyan' }
                'Variable' { 'Green' }
                'Number' { 'Yellow' }
                'StringLiteral' { 'Blue' }
                'Parameter' { 'DarkGray' }
                '^I|Pipe|and' { 'DarkGray' }
                'Operator|GroupStart|GroupEnd|Comment' { 'DarkGray' }
                default { 'White' }
            }
        }
        
        Write-Host $token.Text -NoNewline -ForegroundColor $color
        

        $newPos = [Math]::Min($Code.Length, $token.Extent.EndOffset)
        $totalPos = $newPos
    }
    

    if ($totalPos -lt $Code.Length) {
        $rest = $Code.Substring($totalPos)
        Write-Host $rest -NoNewline -ForegroundColor Gray
    }
    
    Write-Host ""
    try {
        Write-Log -Message "    >> Write Syntax for Highlighting for '$Code'."
        ######################## main code ############################
        $runtime = Get-RunTime -StartRunTime $StartRunTime
        Write-Log -Message "    Run Time: $runtime [h] ###"
        Write-Log -Message "### End Function $CurrentFunction ###"
    }
    catch {
        <#Do this if a terminating exception happens#>
    }

}


#$code = "Get-PSModuleQuantity -ModuleName .\PSModuleQuantityAnalyzer.psd1 | Where-Object {`$_.Type -eq 'Private' -and `$_.References -eq 0} | ft"
#$code = "MATCH (n:Base {highvalue:False})-[r]->(m {highvalue:True}) WHERE NOT type(r) IN ['WriteOwnerRaw','OwnsRaw', 'LocalToComputer']"
#$code = "Get-ADUser -SearchBase 'Ldap:\\dsdadf' -Filter 'homePhone -like 1000' -Properties a,b | Select-Object name,asss | Sort-Object samaccountname  | Format-Table | Out-Host"

#$code = "Get-ADGroupMember -Identity 'Domain Admins' -Recursive | Select-Object -First 10 | Format-Table"
#
#Write-Syntax -Code $code

#$code = "MATCH (s:Base {highvalue:True}) SET s.highvalue = false REMOVE s:Tag_Tier_Zero, s.hvtreason, s.system_tags, s.MemberofTier0Group RETURN s.name"
#Write-Syntax -Code $code

