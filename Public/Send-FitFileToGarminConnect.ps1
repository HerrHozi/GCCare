<#
.SYNOPSIS
Uploads FIT files from a local folder to Garmin Connect.

.DESCRIPTION
`Send-FitFileToGarminConnect` validates the selected import directory, checks for
available `.fit` files, and uploads each file to the Garmin Connect API endpoint
`/upload-service/upload` directly from PowerShell.

Authentication uses the DI OAuth2 token store written by `Get-GarminToken`
(`garmin_tokens.json`). An access token that expires within 15 minutes is
refreshed automatically and saved back.

The files are uploaded in alphabetical order. A failed upload does not stop the
remaining uploads; every file is reported with its own status:
- Uploaded:  Garmin Connect accepted the file.
- Duplicate: Garmin Connect already contains this data (HTTP 409).
- Failed:    The upload failed; `Message` contains the reason.

Returns one result object per file with these properties:
- File:    Name of the FIT file.
- Status:  `Uploaded`, `Duplicate` or `Failed`.
- Message: Error message or Garmin import message, empty when uploaded.

.PARAMETER ImportDirectory
Path to the folder containing `.fit` files.
If omitted, the module default FIT folder is used (`C:\Users\Public\GCCare\FitFiles`).

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `garmin_tokens.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one result object (`File`, `Status`, `Message`) per uploaded FIT file.
Throws when the import directory does not exist or contains no `.fit` files.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`.
- Requires a token file created by `Get-GarminToken`.
- FIT files can be created with `Convert-TanitaExportToFitFile`.

.EXAMPLE
Send-FitFileToGarminConnect

Uploads all FIT files from the default folder C:\Users\Public\GCCare\FitFiles.

.EXAMPLE
Send-FitFileToGarminConnect -ImportDirectory "C:\Data\Garmin\Fit"

Uploads all FIT files from the specified folder.

.EXAMPLE
Send-FitFileToGarminConnect -ImportDirectory "C:\Data\Garmin\Fit" -TokenStore "C:\Temp\.garminconnect"

Uploads all FIT files from the specified folder using a custom token store.

.EXAMPLE
Send-FitFileToGarminConnect | Where-Object Status -eq 'Failed'

Uploads all FIT files and shows only the files that could not be uploaded.
#>
Function Send-FitFileToGarminConnect {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$ImportDirectory = $Script:DefaultFitFilesFolder,
        [string]$TokenStore,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Uploading FIT files to Garmin Connect..."

    if (-not $ImportDirectory) {
        $ImportDirectory = $Script:DefaultFitFilesFolder
    }

    $ImportDirectory = [System.IO.Path]::GetFullPath($ImportDirectory)

    if (-not (Test-Path -LiteralPath $ImportDirectory -PathType Container)) {
        throw "Import directory not found: $ImportDirectory"
    }

    $fitFiles = @(Get-ChildItem -LiteralPath $ImportDirectory -Filter '*.fit' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name)
    if ($fitFiles.Count -eq 0) {
        throw "No .fit files found in import directory: $ImportDirectory"
    }

    Invoke-Output -Type Bullet -Message "Import directory: " -TextMaker $ImportDirectory -NoExtraLines
    Invoke-Output -Type Bullet -Message "FIT files found:  " -TextMaker $fitFiles.Count

    $results = foreach ($fitFile in $fitFiles) {
        $status = 'Uploaded'
        $message = ''

        try {
            $response = Invoke-GarminConnectApi -Path '/upload-service/upload' -Method Post -Form @{ file = $fitFile } -TokenStore $TokenStore

            # Garmin reports rejected files inside the import result
            $failures = @($response.detailedImportResult.failures | Where-Object { $_ })
            if ($failures.Count -gt 0) {
                $status = 'Failed'
                $message = (@($failures.messages.content | Where-Object { $_ }) -join '; ')
                if ($message -match '(?i)duplicate') {
                    $status = 'Duplicate'
                }
            }
        }
        catch {
            $message = $_.Exception.Message
            $status = if ($message -match '\(409\)') { 'Duplicate' } else { 'Failed' }
        }

        switch ($status) {
            'Uploaded' { Invoke-Output -Type Bullet -Message "Uploaded:  " -TextMaker $fitFile.Name -NoExtraLines }
            'Duplicate' { Invoke-Output -Type Bullet -Message "Duplicate: " -TextMaker $fitFile.Name -NoExtraLines }
            'Failed' { Invoke-Output -Type Missing -Message "Failed:    " -TextMaker "$($fitFile.Name) - $message" -NoExtraLines }
        }
        Write-Log -Message "    >> $status : $($fitFile.FullName) $message"

        [pscustomobject]@{
            File    = $fitFile.Name
            Status  = $status
            Message = $message
        }
    }

    $uploadedCount = @($results | Where-Object Status -eq 'Uploaded').Count
    $duplicateCount = @($results | Where-Object Status -eq 'Duplicate').Count
    $failedCount = @($results | Where-Object Status -eq 'Failed').Count

    Write-Host
    Invoke-Output -Type Bullet -Message "Uploaded:         " -TextMaker $uploadedCount -NoExtraLines
    Invoke-Output -Type Bullet -Message "Duplicates:       " -TextMaker $duplicateCount -NoExtraLines
    Invoke-Output -Type Bullet -Message "Failed:           " -TextMaker $failedCount

    if ($failedCount -gt 0) {
        Invoke-Output -Type Warning -Message "$failedCount of $($fitFiles.Count) FIT files could not be uploaded."
    }
    else {
        Invoke-Output -Type Success -Message "FIT upload completed successfully."
    }
    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $results
}
