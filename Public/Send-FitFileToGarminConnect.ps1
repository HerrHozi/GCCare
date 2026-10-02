<#
.SYNOPSIS
Uploads FIT files to Garmin Connect and moves uploaded files to an archive folder.

.DESCRIPTION
`Send-FitFileToGarminConnect` uploads `.fit` files to the Garmin Connect API endpoint
`/upload-service/upload` directly from PowerShell - either all files of an import directory
or the files given with `-Path`.

Authentication uses the DI OAuth2 token store written by `Get-GarminToken`
(`gctoken.json`). If no token exists yet, `Get-GarminToken` is started automatically.
An access token that expires within 15 minutes is refreshed automatically and saved back.

The files are uploaded in alphabetical order. A failed upload does not stop the
remaining uploads; every file is reported with its own status:
- Uploaded:  Garmin Connect accepted the file.
- Duplicate: Garmin Connect already contains this data (HTTP 409).
- Failed:    The upload failed; `Message` contains the reason.

To avoid uploading the same files again, files with the status `Uploaded` or `Duplicate`
are moved to the subfolder `Uploaded` (for example `FitFiles\Uploaded`). Failed files stay
in place, so the next run retries them. An existing file with the same name in the
`Uploaded` folder is replaced. Use `-KeepFiles` to leave all files where they are.

Returns one result object per file with these properties:
- File:    Name of the FIT file.
- Status:  `Uploaded`, `Duplicate` or `Failed`.
- Message: Error message or Garmin import message, empty when uploaded.
- MovedTo: Full path in the `Uploaded` folder, empty when the file was not moved.

.PARAMETER ImportDirectory
Path to the folder containing `.fit` files. Subfolders (including `Uploaded`) are not searched.
If omitted, the module default FIT folder is used (`$env:USERPROFILE\GCCare\FitFiles`).

.PARAMETER Path
One or more FIT files to upload instead of a whole import directory.
Uploaded files are moved to the `Uploaded` subfolder of their own folder.

.PARAMETER UploadedDirectory
Optional folder for uploaded files. Defaults to the subfolder `Uploaded` of the folder the
file comes from. The folder is created when needed.

.PARAMETER KeepFiles
Optional switch to keep uploaded files in place instead of moving them.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `gctoken.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns one result object (`File`, `Status`, `Message`, `MovedTo`) per FIT file.
Returns nothing when there are no new FIT files to upload.
Throws when the import directory or a file given with `-Path` does not exist.

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`.
- FIT files can be created with `Convert-TanitaExportToFitFile`.

.EXAMPLE
Send-FitFileToGarminConnect

Uploads all new FIT files from $env:USERPROFILE\GCCare\FitFiles and moves them to
$env:USERPROFILE\GCCare\FitFiles\Uploaded.

.EXAMPLE
Send-FitFileToGarminConnect -ImportDirectory "C:\Data\Garmin\Fit"

Uploads all FIT files from the specified folder and moves them to C:\Data\Garmin\Fit\Uploaded.

.EXAMPLE
Send-FitFileToGarminConnect -Path "$env:USERPROFILE\GCCare\FitFiles\weight_2026-09-30_06-47.fit"

Uploads a single FIT file.

.EXAMPLE
Send-FitFileToGarminConnect -KeepFiles

Uploads all FIT files from the default folder without moving them.

.EXAMPLE
Send-FitFileToGarminConnect | Where-Object Status -eq 'Failed'

Uploads all new FIT files and shows only the files that could not be uploaded.
#>
Function Send-FitFileToGarminConnect {

    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Directory')]
        [string]$ImportDirectory = $Script:DefaultFitFilesFolder,

        [Parameter(Mandatory = $true, ParameterSetName = 'Files')]
        [string[]]$Path,

        [string]$UploadedDirectory,
        [switch]$KeepFiles,
        [string]$TokenStore,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Uploading FIT files to Garmin Connect..."

    if ($PSCmdlet.ParameterSetName -eq 'Files') {
        $fitFiles = @(foreach ($file in $Path) {
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    throw "FIT file not found: $file"
                }
                Get-Item -LiteralPath $file
            }) | Sort-Object -Property Name
        $fitFiles = @($fitFiles)
        Invoke-Output -Type Bullet -Message "FIT files given:  " -TextMaker $fitFiles.Count
    }
    else {
        if (-not $ImportDirectory) {
            $ImportDirectory = $Script:DefaultFitFilesFolder
        }
        $ImportDirectory = [System.IO.Path]::GetFullPath($ImportDirectory)

        if (-not (Test-Path -LiteralPath $ImportDirectory -PathType Container)) {
            throw "Import directory not found: $ImportDirectory"
        }

        $fitFiles = @(Get-ChildItem -LiteralPath $ImportDirectory -Filter '*.fit' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name)

        Invoke-Output -Type Bullet -Message "Import directory: " -TextMaker $ImportDirectory -NoExtraLines
        Invoke-Output -Type Bullet -Message "FIT files found:  " -TextMaker $fitFiles.Count
    }

    if ($fitFiles.Count -eq 0) {
        Invoke-Output -Type Info -Message "No new FIT files to upload."
        Write-Log -Message "    >> No FIT files found"
        $runtime = Get-RunTime -StartRunTime $StartRunTime
        Write-Log -Message "    Run Time: $runtime [h] ###"
        Write-Log -Message "### End Function $CurrentFunction ###"
        return
    }

    $results = foreach ($fitFile in $fitFiles) {
        $status = 'Uploaded'
        $message = ''
        $movedTo = ''

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

        # Uploaded and duplicate files are already in Garmin Connect: archive them
        if ($status -ne 'Failed' -and -not $KeepFiles) {
            try {
                $targetDirectory = if ($UploadedDirectory) { [System.IO.Path]::GetFullPath($UploadedDirectory) } else { Join-Path -Path $fitFile.DirectoryName -ChildPath 'Uploaded' }
                if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
                    $null = New-Item -Path $targetDirectory -ItemType Directory -Force
                }
                $movedTo = Join-Path -Path $targetDirectory -ChildPath $fitFile.Name
                Move-Item -LiteralPath $fitFile.FullName -Destination $movedTo -Force
            }
            catch {
                $movedTo = ''
                $message = "Uploaded, but could not be moved: $($_.Exception.Message)"
            }
        }

        switch ($status) {
            'Uploaded' { Invoke-Output -Type Bullet -Message "Uploaded:  " -TextMaker $fitFile.Name -NoExtraLines }
            'Duplicate' { Invoke-Output -Type Bullet -Message "Duplicate: " -TextMaker $fitFile.Name -NoExtraLines }
            'Failed' { Invoke-Output -Type Missing -Message "Failed:    " -TextMaker "$($fitFile.Name) - $message" -NoExtraLines }
        }
        Write-Log -Message "    >> $status : $($fitFile.FullName) $message $movedTo"

        [pscustomobject]@{
            File    = $fitFile.Name
            Status  = $status
            Message = $message
            MovedTo = $movedTo
        }
    }

    $uploadedCount = @($results | Where-Object Status -eq 'Uploaded').Count
    $duplicateCount = @($results | Where-Object Status -eq 'Duplicate').Count
    $failedCount = @($results | Where-Object Status -eq 'Failed').Count
    $movedCount = @($results | Where-Object MovedTo).Count

    Write-Host
    Invoke-Output -Type Bullet -Message "Uploaded:         " -TextMaker $uploadedCount -NoExtraLines
    Invoke-Output -Type Bullet -Message "Duplicates:       " -TextMaker $duplicateCount -NoExtraLines
    Invoke-Output -Type Bullet -Message "Failed:           " -TextMaker $failedCount -NoExtraLines
    if ($movedCount -gt 0) {
        Invoke-Output -Type Bullet -Message "Moved to:         " -TextMaker (Split-Path -Path ($results | Where-Object MovedTo | Select-Object -First 1).MovedTo -Parent)
    }
    else {
        Write-Host
    }

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
