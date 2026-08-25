New-Variable -Name GarminLoginSession -Scope Global -Visibility Public -Force

function ConvertTo-UrlEncodedFormBody {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )

    $pairs = foreach ($key in $Data.Keys) {
        $encodedKey = [System.Uri]::EscapeDataString([string]$key)
        $encodedValue = [System.Uri]::EscapeDataString([string]$Data[$key])
        "{0}={1}" -f $encodedKey, $encodedValue
    }

    return ($pairs -join '&')
}

function Get-HtmlInputValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,

        [Parameter(Mandatory = $true)]
        [string]$InputName
    )

    $patternNameBeforeValue = 'name=(?:"|\''){0}(?:"|\'')[^>]*?value=(?:"([^"]*)"|\''([^\'']*)\'')' -f [regex]::Escape($InputName)
    $match = [regex]::Match($Html, $patternNameBeforeValue, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        $patternValueBeforeName = 'value=(?:"([^"]*)"|\''([^\'']*)\'')[^>]*?name=(?:"|\''){0}(?:"|\'')' -f [regex]::Escape($InputName)
        $match = [regex]::Match($Html, $patternValueBeforeName, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if ($match.Success) {
        if (-not [string]::IsNullOrEmpty($match.Groups[1].Value)) {
            return $match.Groups[1].Value
        }

        return $match.Groups[2].Value
    }

    return $null
}

function Get-HtmlHiddenInputValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $result = @{}
    $inputMatches = [regex]::Matches($Html, '(?is)<input\b[^>]*>')

    foreach ($inputMatch in $inputMatches) {
        $inputTag = $inputMatch.Value

        $typeMatch = [regex]::Match($inputTag, '(?i)\btype\s*=\s*(?:"([^"]*)"|\''([^\'']*)\''|([^\s>]+))')
        if ($typeMatch.Success) {
            $typeValue = $typeMatch.Groups[1].Value
            if ([string]::IsNullOrWhiteSpace($typeValue)) {
                $typeValue = $typeMatch.Groups[2].Value
            }
            if ([string]::IsNullOrWhiteSpace($typeValue)) {
                $typeValue = $typeMatch.Groups[3].Value
            }

            if (-not [string]::Equals($typeValue, 'hidden', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }
        else {
            continue
        }

        $nameMatch = [regex]::Match($inputTag, '(?i)\bname\s*=\s*(?:"([^"]*)"|\''([^\'']*)\''|([^\s>]+))')
        if (-not $nameMatch.Success) {
            continue
        }

        $nameValue = $nameMatch.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($nameValue)) {
            $nameValue = $nameMatch.Groups[2].Value
        }
        if ([string]::IsNullOrWhiteSpace($nameValue)) {
            $nameValue = $nameMatch.Groups[3].Value
        }

        if ([string]::IsNullOrWhiteSpace($nameValue)) {
            continue
        }

        $valueMatch = [regex]::Match($inputTag, '(?i)\bvalue\s*=\s*(?:"([^"]*)"|\''([^\'']*)\''|([^\s>]+))')
        $value = ''
        if ($valueMatch.Success) {
            $value = $valueMatch.Groups[1].Value
            if ([string]::IsNullOrWhiteSpace($value) -and $valueMatch.Groups[2].Success) {
                $value = $valueMatch.Groups[2].Value
            }
            if ([string]::IsNullOrWhiteSpace($value) -and $valueMatch.Groups[3].Success) {
                $value = $valueMatch.Groups[3].Value
            }
        }

        $result[$nameValue] = $value
    }

    return $result
}

function Get-MfaActionUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,

        [Parameter(Mandatory = $true)]
        [string]$FallbackBaseUri
    )

    $formActionMatch = [regex]::Match(
        $Html,
        'action=(?:"([^"]*(?:mfa|verify|code)[^"]*)"|\''([^\'']*(?:mfa|verify|code)[^\'']*)\'')',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($formActionMatch.Success) {
        $actionUri = $formActionMatch.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($actionUri)) {
            $actionUri = $formActionMatch.Groups[2].Value
        }

        if ([System.Uri]::IsWellFormedUriString($actionUri, [System.UriKind]::Absolute)) {
            return $actionUri
        }

        return ([System.Uri]::new([System.Uri]$FallbackBaseUri, $actionUri)).AbsoluteUri
    }

    return 'https://sso.garmin.com/sso/verifyMFA/loginEnterMfaCode'
}

function Get-MfaFieldName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $knownNames = @(
        'mfaCode',
        'mfa-code',
        'verificationCode',
        'verification-code',
        'securityCode',
        'security-code',
        'code'
    )

    foreach ($name in $knownNames) {
        if ($Html -match ('name=(?:"|\''){0}(?:"|\'')' -f [regex]::Escape($name))) {
            return $name
        }
    }

    return 'mfaCode'
}



function Publish-TCXToGarmin {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ [IO.Path]::GetExtension($_) -eq '.tcx' })]
        [string]$FilePath
    )

    try {
        if ($null -ne $GarminLoginSession -and $GarminLoginSession -is [Microsoft.PowerShell.Commands.WebRequestSession]) {
            $headers = @{
                'method'          = 'POST'
                'authority'       = 'connect.garmin.com'
                'scheme'          = 'https'
                'path'            = '/modern/proxy/upload-service/upload/.tcx'
                'nk'              = 'NT'
                'dnt'             = '1'
                'x-app-ver'       = '4.33.2.0'
                'x-lang'          = 'en-US'
                'user-agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.125 Safari/537.36 Edg/84.0.522.59'
                'accept'          = '*/*'
                'origin'          = 'https://connect.garmin.com'
                'sec-fetch-site'  = 'same-origin'
                'sec-fetch-mode'  = 'cors'
                'sec-fetch-dest'  = 'empty'
                'referer'         = 'https://connect.garmin.com/modern/import-data'
                'accept-encoding' = 'gzip, deflate, br'
                'accept-language' = 'en-US,en;q=0.9'
            }

            $garminUploadUri = 'https://connect.garmin.com/modern/proxy/upload-service/upload/.tcx'
            $uploadStatus = Invoke-RestMethod -Uri $garminUploadUri -Method POST -Form @{ file = (Get-Item -Path $FilePath) } -WebSession $GarminLoginSession -Headers $headers
            if ($null -ne $uploadStatus -and $uploadStatus.detailedImportResult.successes.Count -ge 1 -and [string]::IsNullOrEmpty($uploadStatus.detailedImportResult.successes[0].messages)) {
                Write-Verbose -Message 'Upload successful!' -Verbose
                return $true
            }

            return $false
        }

        Write-Error -Message 'Invalid login session! Please re-run New-GarminLoginSession Cmdlet and try again.' -ErrorAction Stop
    }
    catch {
        Write-Warning -Message 'Upload failed!'
        Write-Error -Exception $_.Exception -Message $_.Exception.Message -ErrorAction Stop
    }
}

function Get-HtmlFormActionUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,

        [Parameter(Mandatory = $true)]
        [string]$FallbackBaseUri
    )

    $actionMatch = [regex]::Match(
        $Html,
        '<form[^>]*id=(?:"|\'')login-form(?:"|\'')[^>]*action=(?:"([^"]+)"|\''([^\'']+)\'')',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $actionMatch.Success) {
        $actionMatch = [regex]::Match(
            $Html,
            '<form[^>]*action=(?:"([^"]+)"|\''([^\'']+)\'')',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    if ($actionMatch.Success) {
        $actionUri = $actionMatch.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($actionUri)) {
            $actionUri = $actionMatch.Groups[2].Value
        }

        if ([System.Uri]::IsWellFormedUriString($actionUri, [System.UriKind]::Absolute)) {
            return $actionUri
        }

        return ([System.Uri]::new([System.Uri]$FallbackBaseUri, $actionUri)).AbsoluteUri
    }

    return $FallbackBaseUri
}